# frozen_string_literal: true

require "fileutils"
require "optparse"
require "json"
require_relative "output_writer"
require_relative "reproducibility_manifest"

module Shellfie
  module CLIGenerate
    ANIMATED_FORMATS = %w[gif webp apng mp4 webm png-sequence].freeze
    STATIC_FORMATS = %w[png svg svg-raster webp html].freeze
    SEMANTIC_FORMATS = %w[txt json].freeze
    SUPPORTED_FORMATS = (STATIC_FORMATS + ANIMATED_FORMATS + SEMANTIC_FORMATS).uniq.freeze

    private

    def run_generate
      build_generate_parser.parse!(@args)
      input_files = expand_input_paths(@args)
      raise ConfigError, "Input file is required" if input_files.empty?
      raise ConfigError, "Output file is required (use -o option)" unless @options[:output]
      raise ConfigError, "stdout output supports only one input file" if @options[:output] == "-" && input_files.size > 1
      raise ConfigError, "--format is required when writing to stdout" if @options[:output] == "-" && !@options[:format]
      raise ConfigError, "--manifest cannot be used when writing output to stdout" if @options[:output] == "-" && @options[:manifest]
      jobs = input_files.map do |input_file|
        config = apply_overrides(Parser.parse(input_file))
        animate = animation_output?(config)
        format = output_format_for(@options[:output], animate)
        output_path = output_path_for(input_file, format, multiple: input_files.size > 1)
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

      manifests = []
      preflight_render_dependencies!(jobs.map { |_config, _animate, format, _output_path| format })
      jobs.each do |_config, _animate, format, output_path|
        if format == "png-sequence" && Dir.exist?(output_path) && !replaceable_png_sequence_directory?(output_path)
          raise FileSystemError, "Refusing to replace a non-Shellfie directory: #{output_path}"
        end
      end
      jobs.each { |_config, _animate, _format, output_path| ensure_output_writable!(output_path) }
      ensure_output_writable!(@options[:manifest]) if @options[:manifest]
      jobs.each do |config, animate, format, output_path|
        write_rendered_output(config, output_path, animate: animate, format: format)
        manifests << ReproducibilityManifest.build(config, output_path: output_path, format: format) if @options[:manifest]
      end
      write_manifest(manifests) if @options[:manifest]
    end

    def build_generate_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: shellfie generate INPUT_FILE [options]"
        opts.on("-o", "--output PATH", "Output file path (required)") { |path| @options[:output] = path }
        opts.on("-t", "--theme NAME", "Override theme (macos, ubuntu, windows)") { |theme| @options[:theme] = theme }
        opts.on("-a", "--animate", "Generate animated GIF") { @options[:animate] = true }
        opts.on("-s", "--scale FACTOR", "Output scale (1, 2, 3)") { |scale| @options[:scale] = parse_scale(scale) }
        opts.on("-w", "--width PIXELS", Integer, "Override width") { |width| @options[:width] = width }
        opts.on("--typing-rate CPS", Integer, "Typing rate in characters per second") do |rate|
          @options[:typing_rate] = parse_rate(rate)
        end
        opts.on("--framerate FPS", Integer, "Output timing precision in frames per second") do |fps|
          @options[:framerate] = parse_framerate(fps)
        end
        opts.on("--fps FPS", Integer, "Deprecated alias for --framerate") { |fps| @options[:framerate] = parse_framerate(fps) }
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
        opts.on("--format FORMAT", "Output format (png, gif, svg, svg-raster, webp, apng, mp4, webm, png-sequence, html, txt, json)") { |format| @options[:format] = parse_format(format) }
        opts.on("--force", "Overwrite existing output files") { @options[:force] = true }
        opts.on("--quiet", "Suppress non-error output") { @options[:quiet] = true }
        opts.on("--verbose", "Print extra progress information") { @options[:verbose] = true }
        opts.on("--manifest PATH", "Write a reproducibility manifest") { |path| @options[:manifest] = path }
      end
    end

    def write_rendered_output(config, output_path, animate:, format:)
      $stdout.binmode if output_path == "-"
      result = if SEMANTIC_FORMATS.include?(format)
                 TranscriptRenderer.new(config).render(output_path, format: format, io: output_path == "-" ? $stdout : nil)
               elsif animate
                 generate_animation(config, output_path, format)
               else
                 generate_static_image(config, output_path, format)
               end
      $stderr.puts "Generated: #{result}" unless output_path == "-" || @options[:quiet]
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
      {}.tap do |overrides|
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

    def output_path_for(input_file, format, multiple:)
      return @options[:output] if @options[:output] == "-"
      return @options[:output] unless multiple || batch_directory?(@options[:output], format)

      File.join(@options[:output], "#{File.basename(input_file, File.extname(input_file))}.#{format}")
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
