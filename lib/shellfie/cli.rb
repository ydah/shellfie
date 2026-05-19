# frozen_string_literal: true

require "optparse"
require_relative "../shellfie"
require_relative "cli_generate"
require_relative "cli_info"
require_relative "dependency_checker"

module Shellfie
  class CLI
    include CLIGenerate
    include CLIInfo

    COMMANDS = %w[generate init themes validate inspect doctor version help].freeze

    def initialize(args)
      @args = args.dup
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
      when "inspect"
        run_inspect
      when "doctor"
        run_doctor
      when "version", "-v", "--version"
        run_version
      when "help", "-h", "--help"
        show_help
      else
        warn_error "Unknown command: #{command}"
        warn_error "Run 'shellfie help' for usage information."
        exit 1
      end
    rescue Shellfie::Error => e
      warn_error "Error: #{e.message}"
      exit determine_exit_code(e)
    rescue OptionParser::ParseError => e
      warn_error "Error: #{e.message}"
      exit 1
    end

    private

    def warn_error(message)
      $stderr.puts message
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
      else
        1
      end
    end
  end
end
