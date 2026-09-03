# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative '../output_writer'
require_relative '../reproducibility_manifest'

module Shellfie
  class CLI
    module Generate
      ANIMATED_FORMATS = %w[gif webp apng mp4 webm png-sequence].freeze
      STATIC_FORMATS = %w[png svg svg-raster webp html].freeze
      SEMANTIC_FORMATS = %w[txt ansi json asciicast cast].freeze
      SUPPORTED_FORMATS = (STATIC_FORMATS + ANIMATED_FORMATS + SEMANTIC_FORMATS).uniq.freeze
      ASPECT_PRESETS = {
        'readme' => { width: 800, height: 450 },
        'ogp' => { width: 1200, height: 630 },
        'widescreen' => { width: 1280, height: 720 },
        'standard' => { width: 960, height: 720 },
        'vertical' => { width: 720, height: 1280 }
      }.freeze

      private

      def run_generate(options)
        input_files = expand_input_paths(@args)
        validate_generate_request(input_files, options)
        default_output = options.output.nil?
        jobs = build_render_jobs(input_files, options, default_output: default_output)
        input_paths = source_paths_for(jobs, input_files)

        validate_render_job_paths(jobs, input_paths)
        validate_manifest_path(jobs, input_paths, options)
        preflight_render_jobs(jobs, options)

        manifests = render_jobs(jobs, options)
        write_manifest(manifests, options) if options.manifest
      end

      def validate_generate_request(input_files, options)
        raise ConfigError, 'Input file is required' if input_files.empty?
        raise ConfigError, 'Output is required when reading stdin' if !options.output && input_files.include?('-')
        if options.output == '-' && input_files.size > 1
          raise ConfigError,
                'stdout output supports only one input file'
        end
        raise ConfigError, '--format is required when writing to stdout' if options.output == '-' && !options.format
        if options.output == '-' && options.manifest
          raise ConfigError,
                '--manifest cannot be used when writing output to stdout'
        end
        raise ConfigError, '--check cannot write to stdout' if options.output == '-' && options.check
        if options.check && (options.force || options.manifest)
          raise ConfigError,
                '--check cannot be combined with --force or --manifest'
        end
      end

      def build_render_jobs(input_files, options, default_output:)
        configs = input_files.to_h { |input_file| [input_file, apply_overrides(Parser.parse(input_file), options)] }
        input_files.map do |input_file|
          config = configs.fetch(input_file)
          animate = animation_output?(config, options)
          format = render_format_for(options, animate, default_output: default_output)
          output_path = output_path_for(input_file, format, multiple: input_files.size > 1, config: config,
                                                            options: options, default_output: default_output)
          if output_path == '-' && format == 'png-sequence'
            raise ConfigError,
                  'PNG sequence output cannot be written to stdout'
          end

          validate_output_mode(format, animate, options)
          [config, animate, format, output_path]
        end
      end

      def render_format_for(options, animate, default_output:)
        return options.format || (animate ? 'gif' : 'png') if default_output

        output_format_for(options.output, animate, options)
      end

      def source_paths_for(jobs, input_files)
        jobs.flat_map { |config, _animate, _format, _output| config.source_paths }
            .concat(input_files.reject { |path| path == '-' })
            .map { |path| canonical_output_path(path) }
            .uniq
      end

      def validate_render_job_paths(jobs, input_paths)
        duplicate = jobs.group_by(&:last).find { |_path, grouped| grouped.size > 1 }&.first
        raise ConfigError, "Multiple inputs resolve to the same output: #{duplicate}" if duplicate

        output_collision = jobs.find do |_config, _animate, _format, output_path|
          output_path != '-' && input_paths.include?(canonical_output_path(output_path))
        end
        raise ConfigError, "Generated output conflicts with an input file: #{output_collision.last}" if output_collision

        directory_collision = jobs.find do |_config, _animate, format, output_path|
          next false unless format == 'png-sequence'

          directory = canonical_output_path(output_path)
          input_paths.any? { |path| path_within?(path, directory) }
        end
        if directory_collision
          raise ConfigError, "PNG sequence output contains an input file: #{directory_collision.last}"
        end
      end

      def validate_manifest_path(jobs, input_paths, options)
        return unless options.manifest

        raise ConfigError, 'Manifest output cannot be stdout' if options.manifest == '-'

        manifest_path = canonical_output_path(options.manifest)
        collision = jobs.any? do |_config, _animate, _format, output_path|
          output_path != '-' && canonical_output_path(output_path) == manifest_path
        end
        raise ConfigError, "Manifest path conflicts with a generated output: #{options.manifest}" if collision
        if input_paths.include?(manifest_path)
          raise ConfigError,
                "Manifest path conflicts with an input file: #{options.manifest}"
        end

        sequence_dirs = jobs.filter_map do |_config, _animate, format, output_path|
          canonical_output_path(output_path) if format == 'png-sequence'
        end
        nested = sequence_dirs.any? do |directory|
          path_within?(manifest_path, directory) || path_within?(directory, manifest_path)
        end
        raise ConfigError, "Manifest path conflicts with a PNG sequence directory: #{options.manifest}" if nested
      end

      def preflight_render_jobs(jobs, options)
        preflight_render_dependencies(jobs.map { |_config, _animate, format, _output_path| format })
        jobs.each do |_config, _animate, format, output_path|
          if format == 'png-sequence' && Dir.exist?(output_path) && !replaceable_png_sequence_directory?(output_path)
            raise FileSystemError, "Refusing to replace a non-Shellfie directory: #{output_path}"
          end
        end
        jobs.each do |_config, _animate, _format, output_path|
          if options.check
            raise FileSystemError, "Output is missing: #{output_path}" unless File.exist?(output_path)
          else
            ensure_output_writable(output_path, options)
          end
        end
        ensure_output_writable(options.manifest, options) if options.manifest
      end

      def render_jobs(jobs, options)
        workers = [options.jobs || 1, jobs.size].min
        return jobs.filter_map { |job| render_job(job, options) } if workers <= 1

        queue = Queue.new
        jobs.each_with_index { |job, index| queue << [index, job] }
        results = Array.new(jobs.size)
        errors = Queue.new
        Array.new(workers) do
          Thread.new do
            loop do
              index, job = queue.pop(true)
              results[index] = render_job(job, options)
            rescue ThreadError
              break
            rescue StandardError => e
              errors << e
            end
          end
        end.each(&:join)
        raise errors.pop unless errors.empty?

        results.compact
      end

      def render_job(job, options)
        config, animate, format, output_path = job
        if options.check
          verify_rendered_output(config, output_path, animate: animate, format: format, options: options)
        else
          write_rendered_output(config, output_path, animate: animate, format: format, options: options)
        end
        ReproducibilityManifest.build(config, output_path: output_path, format: format) if options.manifest
      end

      def write_rendered_output(config, output_path, animate:, format:, options:, announce: true)
        $stdout.binmode if output_path == '-'
        result = if SEMANTIC_FORMATS.include?(format)
                   Rendering::TranscriptRenderer.new(config).render(output_path, format: format,
                                                                                 io: output_path == '-' ? $stdout : nil)
                 elsif animate
                   generate_animation(config, output_path, format, options)
                 else
                   generate_static_image(config, output_path, format, options)
                 end
        warn "Generated: #{result}" if announce && output_path != '-' && !options.quiet
      end

      def verify_rendered_output(config, output_path, animate:, format:, options:)
        Dir.mktmpdir('shellfie-check') do |dir|
          candidate = format == 'png-sequence' ? File.join(dir, 'sequence') : File.join(dir, "output.#{format}")
          write_rendered_output(config, candidate, animate: animate, format: format, options: options, announce: false)
          expected = ReproducibilityManifest.output_digest(output_path)
          actual = ReproducibilityManifest.output_digest(candidate)
          raise ValidationError, "Generated output is stale: #{output_path}" unless expected == actual
        end
        warn "Current: #{output_path}" unless options.quiet
        output_path
      end

      def generate_animation(config, output_path, format, options)
        warn_verbose("Rendering animation to #{output_path}", options)
        Animation::Generator.new(config).generate(
          output_path,
          scale: options.scale || 1,
          shadow: options.shadow != false,
          transparent: options.transparent || false,
          format: format,
          io: output_path == '-' ? $stdout : nil
        )
      end

      def generate_static_image(config, output_path, format, options)
        warn_verbose("Rendering image to #{output_path}", options)
        Renderer.new(config).render(
          output_path,
          scale: options.scale || 1,
          shadow: options.shadow != false,
          transparent: options.transparent || false,
          format: format,
          io: output_path == '-' ? $stdout : nil
        )
      end

      def apply_overrides(config, options)
        window_overrides = build_window_overrides(options)
        animation_overrides = build_animation_overrides(options)
        return config if [options.theme, options.headless].all?(&:nil?) &&
                         window_overrides.empty? &&
                         animation_overrides.empty?

        values = config.to_h.merge(
          theme: options.theme || config.theme,
          window: config.window.merge(window_overrides),
          animation: config.animation.merge(animation_overrides),
          lines: config.lines,
          frames: config.frames,
          headless: options.headless || config.headless,
          source_paths: config.source_paths
        )
        Config.new(values)
      end

      def build_window_overrides(options)
        (options.preset ? ASPECT_PRESETS.fetch(options.preset).merge(exact_size: true) : {}).tap do |overrides|
          overrides[:width] = options.width if options.width
          overrides[:overflow] = options.overflow if options.overflow
          overrides[:wrap] = options.wrap unless options.wrap.nil?
          overrides[:exact_size] = true if options.exact_size
        end
      end

      def build_animation_overrides(options)
        {}.tap do |overrides|
          overrides[:typing_speed] = (1_000.0 / options.typing_rate).round if options.typing_rate
          overrides[:framerate] = options.framerate if options.framerate
          overrides[:playback_speed] = options.playback_speed if options.playback_speed
          overrides[:seed] = options.seed unless options.seed.nil?
        end
      end

      def validate_output_mode(format, animate, options)
        raise ConfigError, 'MP4 output does not support transparency' if format == 'mp4' && options.transparent

        if SEMANTIC_FORMATS.include?(format)
          return
        elsif animate && ANIMATED_FORMATS.include?(format)
          return
        elsif !animate && STATIC_FORMATS.include?(format)
          return
        end

        mode = animate ? 'animated' : 'static'
        raise ConfigError, "#{mode} output does not support .#{format}"
      end

      def ensure_output_writable(path, options)
        return if path == '-'

        if File.exist?(path) && !options.force
          raise FileSystemError, "Output file already exists: #{path} (use --force to overwrite)"
        end

        directory = File.dirname(File.expand_path(path))
        directory = File.dirname(directory) until File.exist?(directory)
        return if File.directory?(directory) && File.writable?(directory)

        raise FileSystemError, "Output directory is not writable: #{directory}"
      end

      def preflight_render_dependencies(formats)
        DependencyChecker.ensure_imagemagick if (formats - %w[svg html txt json]).any?
        DependencyChecker.ensure_ffmpeg if (formats & %w[apng mp4 webm]).any?
      end

      def expand_input_paths(args)
        args.flat_map do |path|
          next path if path == '-'

          matches = path.match?(/[*?\[]/) ? Dir.glob(path) : [path]
          matches.sort
        end
      end

      def animation_output?(config, options)
        options.animate || config.animated?
      end

      def output_format_for(path, animate, options)
        return options.format if options.format
        return animate ? 'gif' : 'png' if path == '-' || batch_directory?(path)

        extension = File.extname(path).delete_prefix('.').downcase
        if extension.empty?
          animate ? 'gif' : 'png'
        else
          extension
        end
      end

      def output_path_for(input_file, format, multiple:, config:, options:, default_output: false)
        name = File.basename(input_file, File.extname(input_file))
        return File.join(File.dirname(input_file), "#{name}.#{format}") if default_output
        return options.output if options.output == '-'

        if options.output.include?('{')
          path = options.output.gsub('{name}', name)
                        .gsub('{theme}', config.theme)
                        .gsub('{scale}', (options.scale || 1).to_s)
                        .gsub('{format}', format)
          raise ValidationError, "Unknown output template placeholder: #{path[/\{[^}]+\}/]}" if path.match?(/\{[^}]+\}/)

          return path
        end
        return options.output unless multiple || batch_directory?(options.output, format)

        File.join(options.output, "#{name}.#{format}")
      end

      def batch_directory?(path, format = nil)
        path.end_with?(File::SEPARATOR) || (Dir.exist?(path) && format != 'png-sequence')
      end

      def warn_verbose(message, options)
        warn message if options.verbose && !options.quiet
      end

      def write_manifest(manifests, options)
        path = options.manifest
        if File.exist?(path) && !options.force
          raise FileSystemError,
                "Manifest already exists: #{path} (use --force to overwrite)"
        end

        FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
        value = manifests.size == 1 ? manifests.first : manifests
        OutputWriter.write(path, extension: 'json') do |temporary_path|
          File.write(temporary_path, JSON.pretty_generate(value))
        end
        warn "Manifest: #{path}" unless options.quiet
      end
    end
  end
end
