# frozen_string_literal: true

require 'json'
require 'yaml'
require 'cgi/escape'

module Shellfie
  class CLI
    module Info
      VALIDATION_FORMATS = %w[text json sarif junit].freeze

      private

      def run_init
        template = File.read(File.join(__dir__, 'templates', 'init.yml'))
        puts template.gsub('{{VERSION}}') { VERSION }
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
        validate_validation_format!(options.format)
        input_file = required_input_file

        if configuration_version(input_file) == 2
          validate_session_config(input_file, options)
        else
          validate_render_config(input_file, options)
        end
      end

      def run_inspect(options)
        input_file = required_input_file
        if configuration_version(input_file) == 2
          inspect_session_config(input_file, json: options.json)
        else
          inspect_render_config(input_file, json: options.json)
        end
      end

      def required_input_file
        @args.shift || raise(ConfigError, 'Input file is required')
      end

      def validate_validation_format!(format)
        return if VALIDATION_FORMATS.include?(format)

        raise ValidationError, 'validation format must be text, json, sarif, or junit'
      end

      def validate_session_config(input_file, options)
        session = Session::Config.parse(input_file)
        return emit_validation_report(options, valid: true, path: input_file,
                                               details: { version: 2, steps: session.steps.size,
                                                          outputs: session.outputs.size }) unless options.format == 'text'

        puts '✓ Session configuration is valid'
        puts "  Steps: #{session.steps.size}"
        puts "  Outputs: #{session.outputs.size}"
      end

      def validate_render_config(input_file, options)
        config = Parser.parse(input_file)
        return emit_validation_report(options, valid: true, path: input_file,
                                               details: { version: 1, theme: config.theme,
                                                          mode: config.animated? ? 'animated' : 'static' }) unless options.format == 'text'

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

      def inspect_session_config(input_file, json:)
        session = Session::Config.parse(input_file)
        info = {
          config: session.to_h,
          mode: session.mode,
          terminal: session.terminal,
          steps: session.steps.size,
          outputs: session.outputs
        }
        return puts(JSON.pretty_generate(info)) if json

        puts 'Session:'
        puts '  Version: 2'
        puts "  Mode: #{session.mode}"
        puts "  Terminal: #{session.terminal[:columns]}x#{session.terminal[:rows]} (#{session.terminal[:shell]})"
        puts "  Steps: #{session.steps.size}"
        puts "  Outputs: #{session.outputs.size}"
      end

      def inspect_render_config(input_file, json:)
        info = Shellfie.inspect_config(input_file)
        info[:unicode] = {
          version: Terminal::TextMetrics::UNICODE_VERSION,
          width_table: Terminal::TextMetrics::WIDTH_TABLE_VERSION,
          ambiguous_width: info.dig(:config, :window, :ambiguous_width) || 1
        }
        return puts(JSON.pretty_generate(info)) if json

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
        message = error&.message
        report = case options.format
                 when 'json' then json_validation_report(valid, path, details, message)
                 when 'sarif' then sarif_validation_report(path, message)
                 when 'junit' then junit_validation_report(valid, path, message)
                 else raise ValidationError, 'validation format must be text, json, sarif, or junit'
                 end
        puts report
      end

      def json_validation_report(valid, path, details, message)
        JSON.pretty_generate(version: 1, valid: valid, path: path, details: details,
                             errors: message ? [{ message: message }] : [])
      end

      def sarif_validation_report(path, message)
        results = if message
                    [{ level: 'error', message: { text: message },
                       locations: path ? [{ physicalLocation: { artifactLocation: { uri: path } } }] : [] }]
                  else
                    []
                  end
        JSON.pretty_generate(
          version: '2.1.0', '$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
          runs: [{ tool: { driver: { name: 'shellfie', version: VERSION } }, results: results }]
        )
      end

      def junit_validation_report(valid, path, message)
        failure = %(<failure message="#{CGI.escapeHTML(message)}">#{CGI.escapeHTML(message)}</failure>) if message
        %(<testsuite name="shellfie validate" tests="1" failures="#{valid ? 0 : 1}"><testcase name="#{CGI.escapeHTML(path || 'configuration')}">#{failure}</testcase></testsuite>)
      end
    end
  end
end
