# frozen_string_literal: true

require "fileutils"
require "optparse"
require "yaml"
require_relative "../cassette"
require_relative "../output_writer"
require_relative "../session_config"

module Shellfie
  module CLI::Run
    private

    def run_session(record: false)
      parser = build_run_parser(record: record)
      parser.parse!(@args)
      input = @args.shift
      raise ConfigError, "Session configuration is required" unless input

      config = SessionConfig.parse(input)
      raise ConfigError, "mode: replay is not executable; use shellfie replay CASSETTE.json" if config.mode == "replay"
      cassette_path = @options[:cassette]
      yaml_path = @options[:yaml]
      raise ConfigError, "record requires --cassette PATH or --yaml PATH" if record && !cassette_path && !yaml_path
      resolved_outputs = resolve_session_outputs(config.outputs, base_dir: config.base_dir, allow_empty: record && (cassette_path || yaml_path))
      preflight_session_artifacts!(resolved_outputs, cassette_path, yaml_path, input_path: config.path)
      preflight_render_dependencies!(resolved_outputs.map { |_path, format, _output| format })
      raise DependencyError, "Live sessions are not supported on native Windows" if Gem.win_platform?

      require_relative "../session_runner"
      session = SessionRunner.new(config).run
      write_cassette(cassette_path, session) if cassette_path
      write_recording(yaml_path, session) if yaml_path
      render_session_outputs(session, config.outputs, base_dir: config.base_dir, theme: config.theme, render: config.render,
                                                      resolved: resolved_outputs)
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
        opts.on("--yaml PATH", "Write an editable compose recording") { |path| @options[:yaml] = path } if record
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

    def render_session_outputs(session, configured_outputs, base_dir:, theme:, render:, resolved: nil)
      resolved ||= resolve_session_outputs(configured_outputs, base_dir: base_dir)
      resolved.each do |path, format, output|
        ensure_output_writable!(path)
        animate = output.fetch(:animate, @options[:animate] || CLI::Generate::ANIMATED_FORMATS.include?(format))
        capture = output[:capture]
        captured_lines = capture && (session.captures[capture] || session.captures[capture.to_sym])
        raise ConfigError, "Unknown capture: #{capture}" if capture && !captured_lines

        config = session.render_config(theme: theme, options: render, animated: animate, lines: captured_lines)
        original_options = @options
        @options = @options.merge(output.slice(:scale, :shadow, :transparent))
        write_rendered_output(config, path, animate: animate, format: format)
      ensure
        @options = original_options
      end
    end

    def resolve_session_outputs(configured_outputs, base_dir:, allow_empty: false)
      outputs = if @options[:output]
                  [{ path: @options[:output], format: @options[:format], animate: @options[:animate] }]
                else
                  configured_outputs
                end
      raise ConfigError, "Output is required with -o or outputs in the session config" if outputs.empty? && !allow_empty

      resolved = outputs.map do |output|
        path = output[:path] == "-" ? "-" : File.expand_path(output[:path], base_dir)
        format = (output[:format] || @options[:format] || File.extname(path).delete_prefix(".")).to_s.downcase
        unless CLI::Generate::SUPPORTED_FORMATS.include?(format)
          raise ValidationError, "format must be one of: #{CLI::Generate::SUPPORTED_FORMATS.join(", ")}"
        end
        animate = output[:animate].nil? ? (@options[:animate] || CLI::Generate::ANIMATED_FORMATS.include?(format)) : output[:animate]
        validate_output_mode!(format, animate)
        raise ConfigError, "Captured screens cannot be rendered as animations" if output[:capture] && animate

        [path, format, output.merge(animate: animate)]
      end
      duplicate = resolved.group_by(&:first).find { |_path, items| items.size > 1 }&.first
      raise ConfigError, "Multiple outputs resolve to the same path: #{duplicate}" if duplicate

      resolved
    end

    def preflight_session_artifacts!(resolved_outputs, cassette_path, yaml_path, input_path: nil)
      metadata = [cassette_path, yaml_path].compact
      raise ConfigError, "Cassette and YAML outputs cannot be stdout" if metadata.include?("-")

      paths = resolved_outputs.filter_map { |path, _format, _output| path unless path == "-" } +
              metadata.map { |path| File.expand_path(path) }
      collision = paths.group_by { |path| canonical_output_path(path) }.find { |_path, items| items.size > 1 }&.first
      raise ConfigError, "Session artifacts resolve to the same path: #{collision}" if collision
      canonical_paths = paths.map { |path| canonical_output_path(path) }
      sequence_dirs = resolved_outputs.filter_map do |path, format, _output|
        canonical_output_path(path) if format == "png-sequence"
      end
      nested = sequence_dirs.find do |directory|
        canonical_paths.any? { |path| path != directory && (path_within?(path, directory) || path_within?(directory, path)) }
      end
      raise ConfigError, "Session artifact conflicts with a PNG sequence directory: #{nested}" if nested
      if input_path && paths.any? { |path| canonical_output_path(path) == canonical_output_path(input_path) }
        raise ConfigError, "Session artifact conflicts with the session configuration: #{input_path}"
      end
      resolved_outputs.each do |path, format, _output|
        if format == "png-sequence" && Dir.exist?(path) && !replaceable_png_sequence_directory?(path)
          raise FileSystemError, "Refusing to replace a non-Shellfie directory: #{path}"
        end
      end

      paths.each { |path| ensure_output_writable!(path) }
      if resolved_outputs.any? { |_path, format, output| format == "mp4" && (@options[:transparent] || output[:transparent]) }
        raise ConfigError, "MP4 output does not support transparency"
      end
    end

    def write_cassette(path, session)
      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
      if File.exist?(path) && !@options[:force]
        raise FileSystemError, "Cassette already exists: #{path} (use --force to overwrite)"
      end

      Cassette.write(path, session)
      $stderr.puts "Recorded: #{path}" unless @options[:quiet]
    end

    def write_recording(path, session)
      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
      if File.exist?(path) && !@options[:force]
        raise FileSystemError, "Recording already exists: #{path} (use --force to overwrite)"
      end

      OutputWriter.write(path, extension: "yml") { |temporary_path| File.write(temporary_path, YAML.dump(session.compose_hash)) }
      $stderr.puts "Recorded: #{path}" unless @options[:quiet]
    end
  end
end
