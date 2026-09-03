# frozen_string_literal: true

require 'json'
require 'yaml'
require 'cgi/escape'

module Shellfie
  class CLI
    module Info
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
        puts 'Available themes:'
        puts
        Themes::Registry.available_themes.each { |theme| puts "  #{theme}" }
        puts
        puts 'Available color schemes:'
        Themes::Registry.available_color_schemes.each { |scheme| puts "  #{scheme}" }
        puts
        puts 'Use: shellfie generate config.yml -o output.png -t THEME_NAME'
      end

      def run_validate(options)
        format = options.format
        raise ValidationError, 'validation format must be text, json, sarif, or junit' unless %w[text json sarif
                                                                                                 junit].include?(format)

        input_file = @args.shift
        raise ConfigError, 'Input file is required' unless input_file

        if configuration_version(input_file) == 2
          session = Session::Config.parse(input_file)
          if format != 'text'
            return emit_validation_report(
              options,
              valid: true,
              path: input_file,
              details: { version: 2, steps: session.steps.size, outputs: session.outputs.size }
            )
          end

          puts '✓ Session configuration is valid'
          puts "  Steps: #{session.steps.size}"
          puts "  Outputs: #{session.outputs.size}"
          return
        end

        config = Parser.parse(input_file)
        if format != 'text'
          return emit_validation_report(
            options,
            valid: true,
            path: input_file,
            details: { version: 1, theme: config.theme, mode: config.animated? ? 'animated' : 'static' }
          )
        end

        puts '✓ Configuration is valid'
        puts "  Theme: #{config.theme}"
        puts "  Title: #{config.title}"
        puts "  Mode: #{config.animated? ? 'animated' : 'static'}"
        puts "  Lines: #{config.lines.size}" if config.static?
        puts "  Source frames: #{config.frames.size}" if config.animated?
        puts "  Estimated render frames: #{Animation::FrameBuilder.new(config).build.size}" if config.animated?
        geometry = Renderer.new(config).estimate
        puts "  Estimated size: #{geometry[:canvas_width]}x#{geometry[:canvas_height]}"
        puts "  Logical size: #{geometry[:logical_width]}x#{geometry[:logical_height]} @#{geometry[:scale]}x"
      end

      def run_inspect(options)
        input_file = @args.shift
        raise ConfigError, 'Input file is required' unless input_file

        if configuration_version(input_file) == 2
          session = Session::Config.parse(input_file)
          info = {
            config: session.to_h,
            mode: session.mode,
            terminal: session.terminal,
            steps: session.steps.size,
            outputs: session.outputs
          }
          return puts(JSON.pretty_generate(info)) if options.json

          puts 'Session:'
          puts '  Version: 2'
          puts "  Mode: #{session.mode}"
          puts "  Terminal: #{session.terminal[:columns]}x#{session.terminal[:rows]} (#{session.terminal[:shell]})"
          puts "  Steps: #{session.steps.size}"
          puts "  Outputs: #{session.outputs.size}"
          return
        end

        info = Shellfie.inspect_config(input_file)
        info[:unicode] = {
          version: Terminal::TextMetrics::UNICODE_VERSION,
          width_table: Terminal::TextMetrics::WIDTH_TABLE_VERSION,
          ambiguous_width: info.dig(:config, :window, :ambiguous_width) || 1
        }
        return puts(JSON.pretty_generate(info)) if options.json

        puts 'Config:'
        puts "  Version: #{info[:config][:version]}"
        puts "  Theme: #{info[:theme]}"
        puts "  Title: #{info[:config][:title]}"
        puts "  Mode: #{info[:config][:frames].empty? ? 'static' : 'animated'}"
        puts "  Lines: #{info[:config][:lines].size}"
        puts "  Frames: #{info[:config][:frames].size}"
        puts "  Estimated size: #{info[:geometry][:canvas_width]}x#{info[:geometry][:canvas_height]}"
        puts "  Logical size: #{info[:geometry][:logical_width]}x#{info[:geometry][:logical_height]} @#{info[:geometry][:scale]}x"
        puts "  Unicode: #{info[:unicode][:version]} (width table #{info[:unicode][:width_table]}, ambiguous=#{info[:unicode][:ambiguous_width]})"
        info.fetch(:fonts, {}).each do |style, font|
          fingerprint = font[:sha256] ? " (sha256: #{font[:sha256]})" : ''
          puts "  Font #{style}: #{font[:name] || 'not found'}#{fingerprint}"
        end
      end

      def run_doctor
        failed = false
        DependencyChecker.doctor.each do |check|
          status = check[:ok] ? 'ok' : 'fail'
          failed ||= !check[:ok]
          puts "#{status.ljust(4)} #{check[:name]}: #{check[:detail]}"
        end
        exit 4 if failed
      end

      def run_version
        puts "shellfie #{VERSION}"
      end

      def emit_validation_report(options, valid:, path:, details: nil, error: nil)
        format = options.format
        message = error&.message
        case format
        when 'json'
          puts JSON.pretty_generate(version: 1, valid: valid, path: path, details: details,
                                    errors: message ? [{ message: message }] : [])
        when 'sarif'
          result = if message
                     [{ level: 'error', message: { text: message },
                        locations: path ? [{ physicalLocation: { artifactLocation: { uri: path } } }] : [] }]
                   else
                     []
                   end
          puts JSON.pretty_generate(
            version: '2.1.0', '$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
            runs: [{ tool: { driver: { name: 'shellfie', version: VERSION } }, results: result }]
          )
        when 'junit'
          failure = %(<failure message="#{CGI.escapeHTML(message)}">#{CGI.escapeHTML(message)}</failure>) if message
          puts %(<testsuite name="shellfie validate" tests="1" failures="#{valid ? 0 : 1}"><testcase name="#{CGI.escapeHTML(path || 'configuration')}">#{failure}</testcase></testsuite>)
        else
          raise ValidationError, 'validation format must be text, json, sarif, or junit'
        end
      end

    end
  end
end
