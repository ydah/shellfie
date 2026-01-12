# frozen_string_literal: true

require "optparse"
require_relative "../shellfie"

module Shellfie
  class CLI
    COMMANDS = %w[generate init themes validate version help].freeze

    def initialize(args)
      @args = args
      @options = {}
    end

    def run
      return show_help if @args.empty?

      command = @args.shift

      case command
      when "generate", "g"
        run_generate
      when "init"
        run_init
      when "themes"
        run_themes
      when "validate"
        run_validate
      when "version", "-v", "--version"
        run_version
      when "help", "-h", "--help"
        show_help
      else
        puts "Unknown command: #{command}"
        puts "Run 'shellfie help' for usage information."
        exit 1
      end
    rescue Shellfie::Error => e
      puts "Error: #{e.message}"
      exit determine_exit_code(e)
    end

    private

    def run_generate
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: shellfie generate INPUT_FILE [options]"

        opts.on("-o", "--output PATH", "Output file path (required)") do |path|
          @options[:output] = path
        end

        opts.on("-t", "--theme NAME", "Override theme (macos, ubuntu, windows)") do |theme|
          @options[:theme] = theme
        end

        opts.on("-a", "--animate", "Generate animated GIF") do
          @options[:animate] = true
        end

        opts.on("-s", "--scale FACTOR", "Output scale (1, 2, 3)") do |scale|
          @options[:scale] = scale.to_i
        end

        opts.on("-w", "--width PIXELS", Integer, "Override width") do |width|
          @options[:width] = width
        end

        opts.on("--no-shadow", "Disable shadow effect") do
          @options[:shadow] = false
        end

        opts.on("--transparent", "Transparent background") do
          @options[:transparent] = true
        end

        opts.on("--no-header", "Disable window header (headless mode)") do
          @options[:headless] = true
        end
      end

      parser.parse!(@args)

      input_file = @args.shift
      raise ConfigError, "Input file is required" unless input_file
      raise ConfigError, "Output file is required (use -o option)" unless @options[:output]

      config = Parser.parse(input_file)

      if @options[:theme] || @options[:width] || @options[:headless]
        config = Config.new(
          theme: @options[:theme] || config.theme,
          title: config.title,
          window: config.window.merge(@options[:width] ? { width: @options[:width] } : {}),
          font: config.font,
          lines: config.lines,
          animation: config.animation,
          frames: config.frames,
          headless: @options[:headless] || config.headless
        )
      end

      if @options[:animate] || config.animated?
        generator = GifGenerator.new(config)
        output = generator.generate(
          @options[:output],
          scale: @options[:scale] || 1,
          shadow: @options[:shadow] != false
        )
      else
        renderer = Renderer.new(config)
        output = renderer.render(
          @options[:output],
          scale: @options[:scale] || 1,
          shadow: @options[:shadow] != false,
          transparent: @options[:transparent] || false
        )
      end

      puts "Generated: #{output}"
    end

    def run_init
      sample_config = <<~YAML
        # Shellfie configuration file
        theme: macos
        title: "Terminal — zsh"

        window:
          width: 600
          padding: 20

        lines:
          - prompt: "$ "
            command: "gem install shellfie"

          - output: |
              Fetching shellfie-#{VERSION}.gem
              Successfully installed shellfie-#{VERSION}
              1 gem installed

          - prompt: "$ "
            command: "shellfie --version"

          - output: "shellfie #{VERSION}"
      YAML

      puts sample_config
    end

    def run_themes
      puts "Available themes:"
      puts
      puts "  macos     - macOS Terminal style (red/yellow/green buttons, left side)"
      puts "  ubuntu    - Ubuntu Terminal style (buttons on right side)"
      puts "  windows   - Windows Terminal style (square corners, icons)"
      puts
      puts "Use: shellfie generate config.yml -o output.png -t THEME_NAME"
    end

    def run_validate
      input_file = @args.shift
      raise ConfigError, "Input file is required" unless input_file

      config = Parser.parse(input_file)
      puts "✓ Configuration is valid"
      puts "  Theme: #{config.theme}"
      puts "  Title: #{config.title}"
      puts "  Lines: #{config.lines.size}"
      puts "  Mode: #{config.animated? ? "animated" : "static"}"
    end

    def run_version
      puts "shellfie #{VERSION}"
    end

    def show_help
      puts <<~HELP
        Shellfie - Terminal screenshot-style image generator

        Usage: shellfie <command> [options]
               shf <command> [options]

        Commands:
          generate    Generate image from configuration file
          init        Output sample configuration
          themes      List available themes
          validate    Validate configuration file
          version     Show version
          help        Show this help

        Generate Options:
          -o, --output PATH      Output file path (required)
          -t, --theme NAME       Override theme (macos, ubuntu, windows)
          -a, --animate          Generate animated GIF
          -s, --scale FACTOR     Output scale (1, 2, 3)
          -w, --width PIXELS     Override width
          --no-shadow            Disable shadow effect
          --no-header            Disable window header (headless mode)
          --transparent          Transparent background

        Examples:
          shellfie generate config.yml -o terminal.png
          shellfie generate config.yml -o demo.gif --animate
          shellfie generate config.yml -o retina.png --scale 2
          shellfie init > my-config.yml
          shellfie themes

          # Short form
          shf generate config.yml -o terminal.png
          shf init > config.yml
      HELP
    end

    def determine_exit_code(error)
      case error
      when ParseError, ValidationError
        2
      when RenderError, ImageError
        3
      when DependencyError
        4
      else
        1
      end
    end
  end
end
