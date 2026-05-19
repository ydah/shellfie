# frozen_string_literal: true

require "fileutils"
require "optparse"

module Shellfie
  module CLIGenerate
    ANIMATED_EXTENSIONS = %w[.gif].freeze
    STATIC_EXTENSIONS = %w[.png].freeze

    private

    def run_generate
      build_generate_parser.parse!(@args)

      input_file = @args.shift
      raise ConfigError, "Input file is required" unless input_file
      raise ConfigError, "Output file is required (use -o option)" unless @options[:output]

      config = apply_overrides(Parser.parse(input_file))
      animate = @options[:animate] || config.animated?

      validate_output_mode!(@options[:output], animate)
      ensure_output_directory!(@options[:output])

      output = animate ? generate_animation(config) : generate_static_image(config)
      puts "Generated: #{output}"
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
      end
    end

    def generate_animation(config)
      GifGenerator.new(config).generate(
        @options[:output],
        scale: @options[:scale] || 1,
        shadow: @options[:shadow] != false,
        transparent: @options[:transparent] || false
      )
    end

    def generate_static_image(config)
      Renderer.new(config).render(
        @options[:output],
        scale: @options[:scale] || 1,
        shadow: @options[:shadow] != false,
        transparent: @options[:transparent] || false
      )
    end

    def apply_overrides(config)
      window_overrides = build_window_overrides
      animation_overrides = build_animation_overrides
      return config if @options.values_at(:theme, :headless).all?(&:nil?) &&
                       window_overrides.empty? &&
                       animation_overrides.empty?

      Config.new(
        theme: @options[:theme] || config.theme,
        title: config.title,
        window: config.window.merge(window_overrides),
        font: config.font,
        lines: config.lines,
        animation: config.animation.merge(animation_overrides),
        cursor: config.cursor,
        frames: config.frames,
        headless: @options[:headless] || config.headless
      )
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

    def validate_output_mode!(path, animate)
      ext = File.extname(path).downcase
      if animate && !ANIMATED_EXTENSIONS.include?(ext)
        raise ConfigError, "Animated output requires a .gif file"
      end
      return if animate || STATIC_EXTENSIONS.include?(ext)

      raise ConfigError, "Static output requires a .png file"
    end

    def ensure_output_directory!(path)
      directory = File.dirname(path)
      return if directory == "." || Dir.exist?(directory)

      FileUtils.mkdir_p(directory)
    end
  end
end
