# frozen_string_literal: true

require "fileutils"
require "optparse"

module Shellfie
  module CLIGenerate
    ANIMATED_FORMATS = %w[gif webp].freeze
    STATIC_FORMATS = %w[png svg webp].freeze
    SUPPORTED_FORMATS = %w[png gif svg webp].freeze

    private

    def run_generate
      build_generate_parser.parse!(@args)
      input_files = expand_input_paths(@args)
      raise ConfigError, "Input file is required" if input_files.empty?
      raise ConfigError, "Output file is required (use -o option)" unless @options[:output]
      raise ConfigError, "stdout output supports only one input file" if @options[:output] == "-" && input_files.size > 1
      raise ConfigError, "--format is required when writing to stdout" if @options[:output] == "-" && !@options[:format]
      input_files.each do |input_file|
        config = apply_overrides(Parser.parse(input_file))
        animate = animation_output?(config)
        format = output_format_for(@options[:output], animate)
        output_path = output_path_for(input_file, format, multiple: input_files.size > 1)
        validate_output_mode!(format, animate)
        ensure_output_writable!(output_path)
        write_rendered_output(config, output_path, animate: animate, format: format)
      end
    end

    def build_generate_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: shellfie generate INPUT_FILE [options]"
        opts.on("-o", "--output PATH", "Output file path (required)") { |path| @options[:output] = path }
        opts.on("-t", "--theme NAME", "Override theme (macos, ubuntu, windows)") { |theme| @options[:theme] = theme }
        opts.on("-a", "--animate", "Generate animated GIF") { @options[:animate] = true }
        opts.on("-s", "--scale FACTOR", "Output scale (1, 2, 3)") { |scale| @options[:scale] = parse_scale(scale) }
        opts.on("-w", "--width PIXELS", Integer, "Override width") { |width| @options[:width] = width }
        opts.on("--fps FPS", Integer, "Typing speed override for animations") { |fps| @options[:fps] = parse_fps(fps) }
        opts.on("--overflow MODE", "Line overflow mode (clip, wrap, scroll)") { |mode| @options[:overflow] = mode }
        opts.on("--wrap", "Wrap long lines") { @options[:wrap] = true }
        opts.on("--no-wrap", "Clip long lines") { @options[:wrap] = false }
        opts.on("--exact-size", "Make output canvas match the configured window size") { @options[:exact_size] = true }
        opts.on("--no-shadow", "Disable shadow effect") { @options[:shadow] = false }
        opts.on("--transparent", "Transparent background") { @options[:transparent] = true }
        opts.on("--no-header", "Disable window header (headless mode)") { @options[:headless] = true }
        opts.on("--format FORMAT", "Output format (png, gif, svg, webp)") { |format| @options[:format] = parse_format(format) }
        opts.on("--force", "Overwrite existing output files") { @options[:force] = true }
        opts.on("--quiet", "Suppress non-error output") { @options[:quiet] = true }
        opts.on("--verbose", "Print extra progress information") { @options[:verbose] = true }
      end
    end

    def write_rendered_output(config, output_path, animate:, format:)
      result = animate ? generate_animation(config, output_path, format) : generate_static_image(config, output_path, format)
      if output_path == "-"
        $stdout.binmode
        $stdout.write(result)
      else
        puts "Generated: #{result}" unless @options[:quiet]
      end
    end

    def generate_animation(config, output_path, format)
      warn_verbose "Rendering animation to #{output_path}"
      GifGenerator.new(config).generate(
        output_path,
        scale: @options[:scale] || 1,
        shadow: @options[:shadow] != false,
        transparent: @options[:transparent] || false,
        format: format
      )
    end

    def generate_static_image(config, output_path, format)
      warn_verbose "Rendering image to #{output_path}"
      Renderer.new(config).render(
        output_path,
        scale: @options[:scale] || 1,
        shadow: @options[:shadow] != false,
        transparent: @options[:transparent] || false,
        format: format
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
        headless: @options[:headless] || config.headless
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
        overrides[:typing_speed] = (1_000.0 / @options[:fps]).round if @options[:fps]
      end
    end

    def parse_scale(value)
      scale = Integer(value, exception: false)
      return scale if [1, 2, 3].include?(scale)
      raise ValidationError, "scale must be 1, 2, or 3"
    end

    def parse_fps(value)
      fps = Integer(value, exception: false)
      return fps if fps && fps.between?(1, 60)
      raise ValidationError, "fps must be between 1 and 60"
    end

    def parse_format(value)
      format = value.to_s.downcase
      return format if SUPPORTED_FORMATS.include?(format)
      raise ValidationError, "format must be one of: #{SUPPORTED_FORMATS.join(", ")}"
    end

    def validate_output_mode!(format, animate)
      if animate && ANIMATED_FORMATS.include?(format)
        return
      elsif !animate && STATIC_FORMATS.include?(format)
        return
      end

      mode = animate ? "animated" : "static"
      raise ConfigError, "#{mode} output does not support .#{format}"
    end

    def ensure_output_writable!(path)
      return if path == "-"

      directory = File.dirname(path)
      FileUtils.mkdir_p(directory) unless directory == "." || Dir.exist?(directory)
      return if @options[:force] || !File.exist?(path)

      raise FileSystemError, "Output file already exists: #{path} (use --force to overwrite)"
    end

    def expand_input_paths(args)
      args.flat_map do |path|
        next path if path == "-"

        matches = path.match?(/[*?\[]/) ? Dir.glob(path) : [path]
        matches.sort
      end
    end

    def animation_output?(config)
      return true if @options[:format] == "gif"

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
      return @options[:output] unless multiple || batch_directory?(@options[:output])

      File.join(@options[:output], "#{File.basename(input_file, File.extname(input_file))}.#{format}")
    end

    def batch_directory?(path)
      path.end_with?(File::SEPARATOR) || Dir.exist?(path)
    end

    def warn_verbose(message)
      $stderr.puts message if @options[:verbose] && !@options[:quiet]
    end
  end
end
