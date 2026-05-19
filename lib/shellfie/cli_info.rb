# frozen_string_literal: true

module Shellfie
  module CLIInfo
    private

    def run_init
      puts <<~YAML
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
    end

    def run_themes
      puts "Available themes:"
      puts
      ThemeRegistry.available_themes.each { |theme| puts "  #{theme}" }
      puts
      puts "Available color schemes:"
      ThemeRegistry.available_color_schemes.each { |scheme| puts "  #{scheme}" }
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
      puts "  Mode: #{config.animated? ? "animated" : "static"}"
      puts "  Lines: #{config.lines.size}" if config.static?
      puts "  Source frames: #{config.frames.size}" if config.animated?
      puts "  Estimated render frames: #{AnimationFrameBuilder.new(config).build.size}" if config.animated?
      geometry = Renderer.new(config).estimate
      puts "  Estimated size: #{geometry[:canvas_width]}x#{geometry[:canvas_height]}"
    end

    def run_inspect
      input_file = @args.shift
      raise ConfigError, "Input file is required" unless input_file

      info = Shellfie.inspect_config(input_file)
      puts "Config:"
      puts "  Version: #{info[:config][:version]}"
      puts "  Theme: #{info[:theme]}"
      puts "  Title: #{info[:config][:title]}"
      puts "  Mode: #{info[:config][:frames].empty? ? "static" : "animated"}"
      puts "  Lines: #{info[:config][:lines].size}"
      puts "  Frames: #{info[:config][:frames].size}"
      puts "  Estimated size: #{info[:geometry][:canvas_width]}x#{info[:geometry][:canvas_height]}"
    end

    def run_doctor
      failed = false
      DependencyChecker.doctor.each do |check|
        status = check[:ok] ? "ok" : "fail"
        failed ||= !check[:ok]
        puts "#{status.ljust(4)} #{check[:name]}: #{check[:detail]}"
      end
      exit 4 if failed
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
          inspect     Print resolved config and estimated image size
          doctor      Check dependencies and local environment
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
          --fps FPS              Override animation typing FPS
          --overflow MODE        Line overflow mode: clip, wrap, scroll
          --wrap, --no-wrap      Enable or disable long-line wrapping
          --exact-size           Match canvas to configured window size
          --format FORMAT        Output format: png, gif, svg, webp
          --force                Overwrite existing output files
          --quiet                Suppress non-error output
          --verbose              Print progress details

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
  end
end
