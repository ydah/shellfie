# frozen_string_literal: true

require_relative '../shellfie'
require_relative 'dependency_checker'
require_relative 'rendering/transcript_renderer'

module Shellfie
  class CLI
    require_relative 'cli/generate'
    require_relative 'cli/info'
    require_relative 'cli/run'
    require_relative 'cli/authoring'
    require_relative 'cli/options'
    require_relative 'cli/option_parser'

    include Generate
    include Info
    include Run
    include Authoring

    def initialize(args)
      @args = args.dup
    end

    def run
      return puts(OptionParser.help) if @args.empty?

      command = @args.shift
      options = OptionParser.parse(command, @args)
      validation_path = @args.first if command == 'validate'
      dispatch(command, options)
    rescue Shellfie::Error => e
      report_error(e, command, options, validation_path)
    rescue ::OptionParser::ParseError => e
      warn_error "Error: #{e.message}"
      exit 1
    rescue SystemCallError => e
      warn_error "Error: #{e.message}"
      exit 5
    end

    private

    def dispatch(command, options)
      case command
      when 'generate', 'g'
        run_generate(options)
      when 'init'
        run_init
      when 'run'
        run_session(options)
      when 'record'
        record_session(options)
      when 'replay'
        replay_session(options)
      when 'new'
        run_new(options)
      when 'format'
        run_format(options)
      when 'compile'
        run_compile(options)
      when 'schema'
        run_schema
      when 'completion'
        run_completion
      when 'watch'
        run_watch(options)
      when 'themes'
        run_themes
      when 'validate'
        run_validate(options)
      when 'inspect'
        run_inspect(options)
      when 'doctor'
        run_doctor
      when 'version', '-v', '--version'
        run_version
      when 'help', '-h', '--help'
        puts OptionParser.help
      else
        warn_error "Unknown command: #{command}"
        warn_error "Run 'shellfie help' for usage information."
        exit 1
      end
    end

    def report_error(error, command, options, validation_path)
      if command == 'validate' && options&.format != 'text'
        emit_validation_report(options, valid: false, path: validation_path, error: error)
      else
        warn_error "Error: #{error.message}"
      end
      exit determine_exit_code(error)
    end

    def canonical_output_path(path)
      expanded = File.expand_path(path)
      missing = []
      current = expanded
      until File.exist?(current)
        parent = File.dirname(current)
        break if parent == current

        missing.unshift(File.basename(current))
        current = parent
      end
      File.join(File.realpath(current), *missing)
    rescue Errno::ENOENT
      expanded
    end

    def configuration_version(path)
      raw = YAMLSafety.load_file(path, max_bytes: Parser::MAX_INCLUDE_BYTES)
      raw.is_a?(Hash) ? raw[:version] : nil
    end

    def replaceable_png_sequence_directory?(path)
      entries = Dir.children(path)
      entries.empty? || (entries.include?('timeline.json') &&
        entries.all? { |entry| entry == 'timeline.json' || entry.match?(/\Aframe_\d{4}\.png\z/) })
    end

    def path_within?(path, directory)
      path == directory || path.start_with?("#{directory}#{File::SEPARATOR}")
    end

    def warn_error(message)
      warn message
    end

    def determine_exit_code(error)
      case error
      when ParseError, ValidationError
        2
      when RenderError, ImageError
        3
      when DependencyError
        4
      when FileSystemError
        5
      when ExecutionError
        6
      else
        1
      end
    end
  end
end
