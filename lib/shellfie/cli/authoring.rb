# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "tempfile"
require "yaml"

module Shellfie
  module CLI::Authoring
    TEMPLATE_NAMES = %w[static animation run tui ci theme-gallery].freeze

    private

    def run_new
      options = { template: "static" }
      OptionParser.new do |opts|
        opts.on("--template NAME", "static, animation, run, tui, ci, or theme-gallery") { |name| options[:template] = name }
        opts.on("--force", "Overwrite an existing file") { options[:force] = true }
      end.parse!(@args)
      path = @args.shift
      template = options[:template]
      raise ConfigError, "Output path is required" unless path
      raise ValidationError, "unknown template: #{template}" unless TEMPLATE_NAMES.include?(template)
      raise FileSystemError, "File already exists: #{path} (use --force to overwrite)" if File.exist?(path) && !options[:force]

      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
      OutputWriter.write(path, extension: "yml") do |temporary_path|
        File.write(temporary_path, File.read(File.join(__dir__, "templates", "#{template}.yml")))
      end
      puts "Created: #{path}"
    end

    def run_format
      check = false
      OptionParser.new { |opts| opts.on("--check", "Exit unsuccessfully if formatting differs") { check = true } }.parse!(@args)
      path = @args.shift
      raise ConfigError, "Configuration file is required" unless path

      original = YamlSafety.read_file(path, max_bytes: Parser::MAX_INCLUDE_BYTES)
      normalized = YAML.dump(
        YamlSafety.load_file(path, max_bytes: Parser::MAX_INCLUDE_BYTES, symbolize_names: false)
      )
      if check
        raise ValidationError, "Configuration is not formatted: #{path}" unless original == normalized
        puts "Formatted: #{path}"
        return
      end
      return puts("Unchanged: #{path}") if original == normalized

      mode = File.stat(path).mode
      temp = Tempfile.new([File.basename(path), ".tmp"], File.dirname(path))
      temp.write(normalized)
      temp.close
      File.chmod(mode, temp.path)
      FileUtils.mv(temp.path, path)
      puts "Formatted: #{path}"
    ensure
      temp&.close!
    end

    def run_compile
      output_format = "json"
      OptionParser.new do |opts|
        opts.on("--format FORMAT", "json or yaml") { |format| output_format = format }
      end.parse!(@args)
      path = @args.shift
      raise ConfigError, "Configuration file is required" unless path
      raise ValidationError, "compile format must be json or yaml" unless %w[json yaml].include?(output_format)

      version = configuration_version(path)
      value = version == 2 ? SessionConfig.parse(path).to_h : Parser.parse(path).to_h
      puts(output_format == "json" ? JSON.pretty_generate(value) : YAML.dump(value))
    end

    def run_schema
      version = Integer(@args.shift || 1, exception: false)
      raise ValidationError, "schema version must be 1 or 2" unless [1, 2].include?(version)

      puts File.read(File.expand_path("../../../schema/shellfie-v#{version}.schema.json", __dir__))
    end

    def run_completion
      shell = @args.shift || "bash"
      commands = CLI::COMMANDS.join(" ")
      script = case shell
               when "bash" then "complete -W '#{commands}' shellfie shf"
               when "zsh" then "compdef '_arguments \"1:command:(#{commands})\"' shellfie shf"
               when "fish" then commands.split.map { |command| "complete -c shellfie -f -a #{command}" }.join("\n")
               when "powershell", "pwsh"
                 <<~POWERSHELL.chomp
                   Register-ArgumentCompleter -Native -CommandName shellfie,shf -ScriptBlock {
                     param($wordToComplete)
                     '#{commands}'.Split(' ') | Where-Object { $_ -like "$wordToComplete*" }
                   }
                 POWERSHELL
               else raise ValidationError, "completion shell must be bash, zsh, fish, or powershell"
               end
      puts script
    end

    def run_watch
      options = { interval: 0.5 }
      OptionParser.new do |opts|
        opts.on("-o", "--output PATH", "Output path") { |path| options[:output] = path }
        opts.on("--interval SECONDS", Float, "Polling interval") { |value| options[:interval] = value }
      end.parse!(@args)
      input = @args.shift
      raise ConfigError, "Input and -o output are required" unless input && options[:output]
      raise ValidationError, "interval must be positive" unless options[:interval].positive?

      watched = [File.realpath(input)]
      previous = nil
      loop do
        current = watch_snapshot(watched)
        if current != previous
          begin
            version = configuration_version(input)
            config = version == 2 ? SessionConfig.parse(input) : Parser.parse(input)
            watched = config.source_paths
            command = version == 2 ? "run" : "generate"
            CLI.new([command, input, "-o", options[:output], "--force"]).run
          rescue SystemExit
            nil
          rescue Shellfie::Error => e
            warn_error "Error: #{e.message}"
          end
          previous = watch_snapshot(watched)
        end
        sleep options[:interval]
      end
    rescue Interrupt
      puts "Stopped"
    end

    def watch_snapshot(paths)
      paths.to_h do |path|
        modified = File.mtime(path)
        [path, modified]
      rescue SystemCallError
        [path, nil]
      end
    end

  end
end
