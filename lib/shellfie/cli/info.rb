# frozen_string_literal: true

require "json"
require "optparse"
require "yaml"
require "cgi/escape"

module Shellfie
  module CLI::Info
    private

    def run_init
      puts <<~YAML
        # Shellfie configuration file
        version: 1
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
      format = "text"
      OptionParser.new { |opts| opts.on("--format FORMAT", "text, json, sarif, or junit") { |value| format = value } }.parse!(@args)
      raise ValidationError, "validation format must be text, json, sarif, or junit" unless %w[text json sarif junit].include?(format)
      @options[:validation_format] = format
      input_file = @args.shift
      raise ConfigError, "Input file is required" unless input_file
      @options[:validation_path] = input_file

      if configuration_version(input_file) == 2
        session = SessionConfig.parse(input_file)
        return emit_validation_report(valid: true, path: input_file, details: { version: 2, steps: session.steps.size, outputs: session.outputs.size }) if format != "text"

        puts "✓ Session configuration is valid"
        puts "  Steps: #{session.steps.size}"
        puts "  Outputs: #{session.outputs.size}"
        return
      end

      config = Parser.parse(input_file)
      if format != "text"
        return emit_validation_report(
          valid: true, path: input_file,
          details: { version: 1, theme: config.theme, mode: config.animated? ? "animated" : "static" }
        )
      end

      puts "✓ Configuration is valid"
      puts "  Theme: #{config.theme}"
      puts "  Title: #{config.title}"
      puts "  Mode: #{config.animated? ? "animated" : "static"}"
      puts "  Lines: #{config.lines.size}" if config.static?
      puts "  Source frames: #{config.frames.size}" if config.animated?
      puts "  Estimated render frames: #{AnimationFrameBuilder.new(config).build.size}" if config.animated?
      geometry = Renderer.new(config).estimate
      puts "  Estimated size: #{geometry[:canvas_width]}x#{geometry[:canvas_height]}"
      puts "  Logical size: #{geometry[:logical_width]}x#{geometry[:logical_height]} @#{geometry[:scale]}x"
    end

    def run_inspect
      json = false
      OptionParser.new { |opts| opts.on("--json", "Print machine-readable JSON") { json = true } }.parse!(@args)
      input_file = @args.shift
      raise ConfigError, "Input file is required" unless input_file

      if configuration_version(input_file) == 2
        session = SessionConfig.parse(input_file)
        info = {
          config: session.to_h,
          mode: session.mode,
          terminal: session.terminal,
          steps: session.steps.size,
          outputs: session.outputs
        }
        return puts(JSON.pretty_generate(info)) if json

        puts "Session:"
        puts "  Version: 2"
        puts "  Mode: #{session.mode}"
        puts "  Terminal: #{session.terminal[:columns]}x#{session.terminal[:rows]} (#{session.terminal[:shell]})"
        puts "  Steps: #{session.steps.size}"
        puts "  Outputs: #{session.outputs.size}"
        return
      end

      info = Shellfie.inspect_config(input_file)
      info[:unicode] = {
        version: TextMetrics::UNICODE_VERSION,
        width_table: TextMetrics::WIDTH_TABLE_VERSION,
        ambiguous_width: info.dig(:config, :window, :ambiguous_width) || 1
      }
      return puts(JSON.pretty_generate(info)) if json
      puts "Config:"
      puts "  Version: #{info[:config][:version]}"
      puts "  Theme: #{info[:theme]}"
      puts "  Title: #{info[:config][:title]}"
      puts "  Mode: #{info[:config][:frames].empty? ? "static" : "animated"}"
      puts "  Lines: #{info[:config][:lines].size}"
      puts "  Frames: #{info[:config][:frames].size}"
      puts "  Estimated size: #{info[:geometry][:canvas_width]}x#{info[:geometry][:canvas_height]}"
      puts "  Logical size: #{info[:geometry][:logical_width]}x#{info[:geometry][:logical_height]} @#{info[:geometry][:scale]}x"
      puts "  Unicode: #{info[:unicode][:version]} (width table #{info[:unicode][:width_table]}, ambiguous=#{info[:unicode][:ambiguous_width]})"
      info.fetch(:fonts, {}).each do |style, font|
        fingerprint = font[:sha256] ? " (sha256: #{font[:sha256]})" : ""
        puts "  Font #{style}: #{font[:name] || "not found"}#{fingerprint}"
      end
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

    def emit_validation_report(valid:, path: nil, details: nil, error: nil)
      format = @options[:validation_format]
      path ||= @options[:validation_path]
      message = error&.message
      case format
      when "json"
        puts JSON.pretty_generate(version: 1, valid: valid, path: path, details: details, errors: message ? [{ message: message }] : [])
      when "sarif"
        result = if message
                   [{ level: "error", message: { text: message }, locations: path ? [{ physicalLocation: { artifactLocation: { uri: path } } }] : [] }]
                 else
                   []
                 end
        puts JSON.pretty_generate(
          version: "2.1.0", "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
          runs: [{ tool: { driver: { name: "shellfie", version: VERSION } }, results: result }]
        )
      when "junit"
        failure = %(<failure message="#{CGI.escapeHTML(message)}">#{CGI.escapeHTML(message)}</failure>) if message
        puts %(<testsuite name="shellfie validate" tests="1" failures="#{valid ? 0 : 1}"><testcase name="#{CGI.escapeHTML(path || "configuration")}">#{failure}</testcase></testsuite>)
      else
        raise ValidationError, "validation format must be text, json, sarif, or junit"
      end
    end

    def show_help
      puts <<~HELP
        Shellfie - Deterministic terminal visual compiler

        Usage: shellfie <command> [options]
               shf <command> [options]

        Commands:
          generate    Render outputs from a configuration file
          run         Execute and render a version 2 terminal session
          record      Run a session and save a cassette or editable YAML
          replay      Render an existing cassette without executing commands
          new         Create a config from a template
          format      Normalize YAML formatting
          compile     Print the resolved config or session IR
          schema      Print the version 1 or 2 JSON Schema
          completion  Print bash, zsh, fish, or PowerShell completion
          watch       Regenerate when a config or included file changes
          init        Output sample configuration
          themes      List available themes
          validate    Validate configuration file
          inspect     Print resolved config and estimated image size
          doctor      Check dependencies and local environment
          version     Show version
          help        Show this help

        Generate Options:
          -o, --output PATH      Output path/template (defaults beside input)
          -t, --theme NAME       Override theme (macos, ubuntu, windows)
          -a, --animate          Render animated output
          -s, --scale FACTOR     Output scale (1, 2, 3)
          -w, --width PIXELS     Override width
          --no-shadow            Disable shadow effect
          --no-header            Disable window header (headless mode)
          --transparent          Transparent background
          --typing-rate CPS      Typing rate in characters per second
          --framerate FPS        Output timing precision
          --seed N               Deterministic animation jitter seed
          --playback-speed N     Playback speed multiplier
          --fps FPS              Deprecated alias for --framerate
          --overflow MODE        Line overflow mode: clip, wrap, scroll
          --wrap, --no-wrap      Enable or disable long-line wrapping
          --exact-size           Match canvas to configured window size
          --format FORMAT        Also: mp4, webm, png-sequence, html, txt, json
          --force                Overwrite existing output files
          --quiet                Suppress non-error output
          --verbose              Print progress details
          --manifest PATH        Write environment and output fingerprints

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
