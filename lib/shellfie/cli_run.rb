# frozen_string_literal: true

require "fileutils"
require "optparse"
require_relative "cassette"
require_relative "session_config"

module Shellfie
  module CLIRun
    private

    def run_session(record: false)
      parser = build_run_parser(record: record)
      parser.parse!(@args)
      input = @args.shift
      raise ConfigError, "Session configuration is required" unless input

      config = SessionConfig.parse(input)
      require_relative "session_runner"
      session = SessionRunner.new(config).run
      cassette_path = @options[:cassette]
      raise ConfigError, "record requires --cassette PATH" if record && !cassette_path
      write_cassette(cassette_path, session) if cassette_path
      render_session_outputs(session, config.outputs, base_dir: config.base_dir, theme: config.theme, render: config.render)
    end

    def replay_session
      build_replay_parser.parse!(@args)
      input = @args.shift
      raise ConfigError, "Cassette file is required" unless input

      session = Cassette.read(input)
      render_session_outputs(session, [], base_dir: Dir.pwd, theme: @options[:theme] || "macos", render: {})
    end

    def build_run_parser(record:)
      OptionParser.new do |opts|
        opts.banner = "Usage: shellfie #{record ? "record" : "run"} SESSION.yml [options]"
        session_output_options(opts)
        opts.on("--cassette PATH", "Write an offline replay cassette") { |path| @options[:cassette] = path }
      end
    end

    def build_replay_parser
      OptionParser.new do |opts|
        opts.banner = "Usage: shellfie replay SESSION.json [options]"
        session_output_options(opts)
        opts.on("-t", "--theme NAME", "Render theme") { |theme| @options[:theme] = theme }
      end
    end

    def session_output_options(opts)
      opts.on("-o", "--output PATH", "Output path (overrides config outputs)") { |path| @options[:output] = path }
      opts.on("--format FORMAT", "Output format") { |format| @options[:format] = parse_format(format) }
      opts.on("-a", "--animate", "Render the captured timeline") { @options[:animate] = true }
      opts.on("--force", "Overwrite existing outputs") { @options[:force] = true }
      opts.on("--quiet", "Suppress generated paths") { @options[:quiet] = true }
    end

    def render_session_outputs(session, configured_outputs, base_dir:, theme:, render:)
      outputs = if @options[:output]
                  [{ path: @options[:output], format: @options[:format], animate: @options[:animate] }]
                else
                  configured_outputs
                end
      raise ConfigError, "Output is required with -o or outputs in the session config" if outputs.empty?

      resolved = outputs.map do |output|
        path = output[:path] == "-" ? "-" : File.expand_path(output[:path], base_dir)
        format = (output[:format] || @options[:format] || File.extname(path).delete_prefix(".")).to_s.downcase
        unless CLIGenerate::SUPPORTED_FORMATS.include?(format)
          raise ValidationError, "format must be one of: #{CLIGenerate::SUPPORTED_FORMATS.join(", ")}"
        end

        [path, format, output]
      end
      duplicate = resolved.group_by(&:first).find { |_path, items| items.size > 1 }&.first
      raise ConfigError, "Multiple outputs resolve to the same path: #{duplicate}" if duplicate

      resolved.each do |path, format, output|
        ensure_output_writable!(path)
        animate = output.fetch(:animate, @options[:animate] || CLIGenerate::ANIMATED_FORMATS.include?(format))
        config = session.render_config(theme: theme, options: render, animated: animate)
        write_rendered_output(config, path, animate: animate, format: format)
      end
    end

    def write_cassette(path, session)
      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
      if File.exist?(path) && !@options[:force]
        raise FileSystemError, "Cassette already exists: #{path} (use --force to overwrite)"
      end

      Cassette.write(path, session)
      puts "Recorded: #{path}" unless @options[:quiet]
    end
  end
end
