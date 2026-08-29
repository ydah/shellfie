# frozen_string_literal: true

require "fileutils"
require "optparse"
require "json"
require "tmpdir"
require_relative "output_writer"
require_relative "reproducibility_manifest"

module Shellfie
  module CLIGenerate
    ANIMATED_FORMATS = %w[gif webp apng mp4 webm png-sequence].freeze
    STATIC_FORMATS = %w[png svg svg-raster webp html].freeze
    SEMANTIC_FORMATS = %w[txt ansi json asciicast cast].freeze
    SUPPORTED_FORMATS = (STATIC_FORMATS + ANIMATED_FORMATS + SEMANTIC_FORMATS).uniq.freeze
    ASPECT_PRESETS = {
      "readme" => { width: 800, height: 450 },
      "ogp" => { width: 1200, height: 630 },
      "widescreen" => { width: 1280, height: 720 },
      "standard" => { width: 960, height: 720 },
      "vertical" => { width: 720, height: 1280 }
    }.freeze

    private

    def run_generate
      build_generate_parser.parse!(@args)
      input_files = expand_input_paths(@args)
      raise ConfigError, "Input file is required" if input_files.empty?
      raise ConfigError, "Output is required when reading stdin" if !@options[:output] && input_files.include?("-")
      @options[:default_output] = true unless @options[:output]
      raise ConfigError, "stdout output supports only one input file" if @options[:output] == "-" && input_files.size > 1
      raise ConfigError, "--format is required when writing to stdout" if @options[:output] == "-" && !@options[:format]
      raise ConfigError, "--manifest cannot be used when writing output to stdout" if @options[:output] == "-" && @options[:manifest]
      raise ConfigError, "--check cannot write to stdout" if @options[:output] == "-" && @options[:check]
      raise ConfigError, "--check cannot be combined with --force or --manifest" if @options[:check] && (@options[:force] || @options[:manifest])
      configs = input_files.to_h { |input_file| [input_file, apply_overrides(Parser.parse(input_file))] }
      jobs = input_files.map do |input_file|
        config = configs.fetch(input_file)
        animate = animation_output?(config)
        format = @options[:default_output] ? (@options[:format] || (animate ? "gif" : "png")) : output_format_for(@options[:output], animate)
        output_path = output_path_for(input_file, format, multiple: input_files.size > 1, config: config)
        raise ConfigError, "PNG sequence output cannot be written to stdout" if output_path == "-" && format == "png-sequence"
        validate_output_mode!(format, animate)
        [config, animate, format, output_path]
      end
      duplicate = jobs.group_by(&:last).find { |_path, grouped| grouped.size > 1 }&.first
      raise ConfigError, "Multiple inputs resolve to the same output: #{duplicate}" if duplicate
      input_paths = jobs.flat_map { |config, _animate, _format, _output| config.source_paths }
                        .concat(input_files.reject { |path| path == "-" })
                        .map { |path| canonical_output_path(path) }.uniq
      output_collision = jobs.find do |_config, _animate, _format, output_path|
        output_path != "-" && input_paths.include?(canonical_output_path(output_path))
      end
      raise ConfigError, "Generated output conflicts with an input file: #{output_collision.last}" if output_collision
      directory_collision = jobs.find do |_config, _animate, format, output_path|
        next false unless format == "png-sequence"

        directory = canonical_output_path(output_path)
        input_paths.any? { |path| path_within?(path, directory) }
      end
      if directory_collision
        raise ConfigError, "PNG sequence output contains an input file: #{directory_collision.last}"
      end
      if @options[:manifest]
        raise ConfigError, "Manifest output cannot be stdout" if @options[:manifest] == "-"

        manifest_path = canonical_output_path(@options[:manifest])
        collision = jobs.any? do |_config, _animate, _format, output_path|
          output_path != "-" && canonical_output_path(output_path) == manifest_path
        end
        raise ConfigError, "Manifest path conflicts with a generated output: #{@options[:manifest]}" if collision
        raise ConfigError, "Manifest path conflicts with an input file: #{@options[:manifest]}" if input_paths.include?(manifest_path)
        sequence_dirs = jobs.filter_map do |_config, _animate, format, output_path|
          canonical_output_path(output_path) if format == "png-sequence"
        end
        nested = sequence_dirs.any? do |directory|
          path_within?(manifest_path, directory) || path_within?(directory, manifest_path)
        end
        raise ConfigError, "Manifest path conflicts with a PNG sequence directory: #{@options[:manifest]}" if nested
      end

      preflight_render_dependencies!(jobs.map { |_config, _animate, format, _output_path| format })
      jobs.each do |_config, _animate, format, output_path|
        if format == "png-sequence" && Dir.exist?(output_path) && !replaceable_png_sequence_directory?(output_path)
          raise FileSystemError, "Refusing to replace a non-Shellfie directory: #{output_path}"
        end
      end
      jobs.each do |_config, _animate, _format, output_path|
        if @options[:check]
          raise FileSystemError, "Output is missing: #{output_path}" unless File.exist?(output_path)
        else
          ensure_output_writable!(output_path)
        end
      end
      ensure_output_writable!(@options[:manifest]) if @options[:manifest]
      manifests = render_jobs(jobs)
      write_manifest(manifests) if @options[:manifest]
    end

    def build_generate_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: shellfie generate INPUT_FILE [options]"
        opts.on("-o", "--output PATH", "Output path or {name}-{theme}-{scale}.{format} template") { |path| @options[:output] = path }
        opts.on("-t", "--theme NAME", "Override theme (macos, ubuntu, windows)") { |theme| @options[:theme] = theme }
        opts.on("-a", "--animate", "Render animated output") { @options[:animate] = true }
        opts.on("-s", "--scale FACTOR", "Output scale (1, 2, 3)") { |scale| @options[:scale] = parse_scale(scale) }
        opts.on("-w", "--width PIXELS", Integer, "Override width") { |width| @options[:width] = width }
        opts.on("--preset NAME", "readme, ogp, widescreen, standard, or vertical") do |name|
          raise ValidationError, "preset must be one of: #{ASPECT_PRESETS.keys.join(', ')}" unless ASPECT_PRESETS.key?(name)

          @options[:preset] = name
        end
        opts.on("--typing-rate CPS", Integer, "Typing rate in characters per second") do |rate|
          @options[:typing_rate] = parse_rate(rate)
        end
        opts.on("--framerate FPS", Integer, "Output timing precision in frames per second") do |fps|
          @options[:framerate] = parse_framerate(fps)
        end
        opts.on("--fps FPS", Integer, "Deprecated alias for --framerate") do |fps|
          warn_error "Warning: --fps is deprecated; use --framerate"
          @options[:framerate] = parse_framerate(fps)
        end
        opts.on("--seed N", Integer, "Deterministic animation seed") { |seed| @options[:seed] = parse_seed(seed) }
        opts.on("--playback-speed FACTOR", Float, "Playback speed multiplier") do |speed|
          @options[:playback_speed] = parse_playback_speed(speed)
        end
        opts.on("--overflow MODE", "Line overflow mode (clip, wrap, scroll)") { |mode| @options[:overflow] = mode }
        opts.on("--wrap", "Wrap long lines") { @options[:wrap] = true }
        opts.on("--no-wrap", "Clip long lines") { @options[:wrap] = false }
        opts.on("--exact-size", "Make output canvas match the configured window size") { @options[:exact_size] = true }
        opts.on("--no-shadow", "Disable shadow effect") { @options[:shadow] = false }
        opts.on("--transparent", "Transparent background") { @options[:transparent] = true }
        opts.on("--no-header", "Disable window header (headless mode)") { @options[:headless] = true }
        opts.on("--format FORMAT", "Output format (png, gif, svg, svg-raster, webp, apng, mp4, webm, png-sequence, html, txt, ansi, json, asciicast)") { |format| @options[:format] = parse_format(format) }
        opts.on("--force", "Overwrite existing output files") { @options[:force] = true }
        opts.on("--check", "Fail if the existing output differs without replacing it") { @options[:check] = true }
        opts.on("--jobs N", Integer, "Render up to N inputs in parallel (1-32)") { |value| @options[:jobs] = parse_jobs(value) }
        opts.on("--quiet", "Suppress non-error output") { @options[:quiet] = true }
        opts.on("--verbose", "Print extra progress information") { @options[:verbose] = true }
        opts.on("--manifest PATH", "Write a reproducibility manifest") { |path| @options[:manifest] = path }
      end
    end

    def render_jobs(jobs)
      workers = [@options[:jobs] || 1, jobs.size].min
      return jobs.filter_map { |job| render_job(job) } if workers <= 1

      queue = Queue.new
      jobs.each_with_index { |job, index| queue << [index, job] }
      results = Array.new(jobs.size)
      errors = Queue.new
      Array.new(workers) do
        Thread.new do
          loop do
            index, job = queue.pop(true)
            results[index] = render_job(job)
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

    def render_job(job)
      config, animate, format, output_path = job
      if @options[:check]
        check_rendered_output(config, output_path, animate: animate, format: format)
      else
        write_rendered_output(config, output_path, animate: animate, format: format)
      end
      ReproducibilityManifest.build(config, output_path: output_path, format: format) if @options[:manifest]
    end

    def write_rendered_output(config, output_path, animate:, format:, announce: true)
      $stdout.binmode if output_path == "-"
      result = if SEMANTIC_FORMATS.include?(format)
                 TranscriptRenderer.new(config).render(output_path, format: format, io: output_path == "-" ? $stdout : nil)
               elsif animate
                 generate_animation(config, output_path, format)
               else
                 generate_static_image(config, output_path, format)
               end
      $stderr.puts "Generated: #{result}" if announce && output_path != "-" && !@options[:quiet]
    end

    def check_rendered_output(config, output_path, animate:, format:)
      Dir.mktmpdir("shellfie-check") do |dir|
        candidate = format == "png-sequence" ? File.join(dir, "sequence") : File.join(dir, "output.#{format}")
        write_rendered_output(config, candidate, animate: animate, format: format, announce: false)
        expected = ReproducibilityManifest.output_digest(output_path)
        actual = ReproducibilityManifest.output_digest(candidate)
        raise ValidationError, "Generated output is stale: #{output_path}" unless expected == actual
      end
      $stderr.puts "Current: #{output_path}" unless @options[:quiet]
      output_path
    end

    def generate_animation(config, output_path, format)
      warn_verbose "Rendering animation to #{output_path}"
      GifGenerator.new(config).generate(
        output_path,
        scale: @options[:scale] || 1,
        shadow: @options[:shadow] != false,
        transparent: @options[:transparent] || false,
        format: format,
        io: output_path == "-" ? $stdout : nil
      )
    end

    def generate_static_image(config, output_path, format)
      warn_verbose "Rendering image to #{output_path}"
      Renderer.new(config).render(
        output_path,
        scale: @options[:scale] || 1,
        shadow: @options[:shadow] != false,
        transparent: @options[:transparent] || false,
        format: format,
        io: output_path == "-" ? $stdout : nil
      )
    end

    def apply_overrides(config)
      window_overrides = build_window_overrides
      animation_overrides = build_animation_overrides
      return config if @options.values_at(:theme, :headless).all?(&:nil?) &&
                       window_overrides.empty? &&
                       animation_overrides.empty?

      options = config.to_h.merge(
        theme: @options[:theme] || config.theme,
        window: config.window.merge(window_overrides),
        animation: config.animation.merge(animation_overrides),
        lines: config.lines,
        frames: config.frames,
        headless: @options[:headless] || config.headless,
        source_paths: config.source_paths
      )
      Config.new(options)
    end

    def build_window_overrides
      (@options[:preset] ? ASPECT_PRESETS.fetch(@options[:preset]).merge(exact_size: true) : {}).tap do |overrides|
        overrides[:width] = @options[:width] if @options[:width]
        overrides[:overflow] = @options[:overflow] if @options[:overflow]
        overrides[:wrap] = @options[:wrap] unless @options[:wrap].nil?
        overrides[:exact_size] = true if @options[:exact_size]
      end
    end

    def build_animation_overrides
      {}.tap do |overrides|
        overrides[:typing_speed] = (1_000.0 / @options[:typing_rate]).round if @options[:typing_rate]
        overrides[:framerate] = @options[:framerate] if @options[:framerate]
        overrides[:playback_speed] = @options[:playback_speed] if @options[:playback_speed]
        overrides[:seed] = @options[:seed] if @options.key?(:seed)
      end
    end

    def parse_scale(value)
      scale = Integer(value, exception: false)
      return scale if [1, 2, 3].include?(scale)
      raise ValidationError, "scale must be 1, 2, or 3"
    end

    def parse_rate(value)
      rate = Integer(value, exception: false)
      return rate if rate && rate.between?(1, 1_000)
      raise ValidationError, "typing rate must be between 1 and 1000"
    end

    def parse_framerate(value)
      fps = Integer(value, exception: false)
      return fps if fps && fps.between?(1, 120)
      raise ValidationError, "framerate must be between 1 and 120"
    end

    def parse_playback_speed(value)
      speed = Float(value, exception: false)
      return speed if speed&.positive? && speed <= 100
      raise ValidationError, "playback speed must be greater than 0 and at most 100"
    end

    def parse_seed(value)
      seed = Integer(value, exception: false)
      return seed if seed&.between?(0, 2_147_483_647)

      raise ValidationError, "seed must be between 0 and 2147483647"
    end

    def parse_jobs(value)
      jobs = Integer(value, exception: false)
      return jobs if jobs&.between?(1, 32)

      raise ValidationError, "jobs must be between 1 and 32"
    end

    def parse_format(value)
      format = value.to_s.downcase
      return format if SUPPORTED_FORMATS.include?(format)
      raise ValidationError, "format must be one of: #{SUPPORTED_FORMATS.join(", ")}"
    end

    def validate_output_mode!(format, animate)
      raise ConfigError, "MP4 output does not support transparency" if format == "mp4" && @options[:transparent]

      if SEMANTIC_FORMATS.include?(format)
        return
      elsif animate && ANIMATED_FORMATS.include?(format)
        return
      elsif !animate && STATIC_FORMATS.include?(format)
        return
      end

      mode = animate ? "animated" : "static"
      raise ConfigError, "#{mode} output does not support .#{format}"
    end

    def ensure_output_writable!(path)
      return if path == "-"

      if File.exist?(path) && !@options[:force]
        raise FileSystemError, "Output file already exists: #{path} (use --force to overwrite)"
      end

      directory = File.dirname(File.expand_path(path))
      directory = File.dirname(directory) until File.exist?(directory)
      return if File.directory?(directory) && File.writable?(directory)

      raise FileSystemError, "Output directory is not writable: #{directory}"
    end

    def preflight_render_dependencies!(formats)
      DependencyChecker.ensure_imagemagick! if (formats - %w[svg html txt json]).any?
      DependencyChecker.ensure_ffmpeg! if (formats & %w[apng mp4 webm]).any?
    end

    def expand_input_paths(args)
      args.flat_map do |path|
        next path if path == "-"

        matches = path.match?(/[*?\[]/) ? Dir.glob(path) : [path]
        matches.sort
      end
    end

    def animation_output?(config)
      @options[:animate] || config.animated?
    end

    def output_format_for(path, animate)
      return @options[:format] if @options[:format]
      return animate ? "gif" : "png" if path == "-" || batch_directory?(path)

      extension = File.extname(path).delete_prefix(".").downcase
      extension.empty? ? (animate ? "gif" : "png") : extension
    end

    def output_path_for(input_file, format, multiple:, config:)
      name = File.basename(input_file, File.extname(input_file))
      if @options[:default_output]
        return File.join(File.dirname(input_file), "#{name}.#{format}")
      end
      return @options[:output] if @options[:output] == "-"
      if @options[:output].include?("{")
        path = @options[:output].gsub("{name}", name)
                                .gsub("{theme}", config.theme)
                                .gsub("{scale}", (@options[:scale] || 1).to_s)
                                .gsub("{format}", format)
        raise ValidationError, "Unknown output template placeholder: #{path[/\{[^}]+\}/]}" if path.match?(/\{[^}]+\}/)
        return path
      end
      return @options[:output] unless multiple || batch_directory?(@options[:output], format)

      File.join(@options[:output], "#{name}.#{format}")
    end

    def batch_directory?(path, format = nil)
      path.end_with?(File::SEPARATOR) || (Dir.exist?(path) && format != "png-sequence")
    end

    def warn_verbose(message)
      $stderr.puts message if @options[:verbose] && !@options[:quiet]
    end

    def write_manifest(manifests)
      path = @options[:manifest]
      raise FileSystemError, "Manifest already exists: #{path} (use --force to overwrite)" if File.exist?(path) && !@options[:force]

      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
      value = manifests.size == 1 ? manifests.first : manifests
      OutputWriter.write(path, extension: "json") { |temporary_path| File.write(temporary_path, JSON.pretty_generate(value)) }
      $stderr.puts "Manifest: #{path}" unless @options[:quiet]
    end
  end
end
