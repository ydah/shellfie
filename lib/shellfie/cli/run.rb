# frozen_string_literal: true

require 'fileutils'
require 'yaml'
require_relative '../session/cassette'
require_relative '../output_writer'
require_relative '../session/config'

module Shellfie
  module CLI::Run
    private

    def run_session(options, record: false)
      input = @args.shift
      raise ConfigError, 'Session configuration is required' unless input

      config = SessionConfig.parse(input)
      raise ConfigError, 'mode: replay is not executable; use shellfie replay CASSETTE.json' if config.mode == 'replay'

      cassette_path = options.cassette
      yaml_path = options.yaml
      raise ConfigError, 'record requires --cassette PATH or --yaml PATH' if record && !cassette_path && !yaml_path

      resolved_outputs = resolve_session_outputs(
        config.outputs,
        base_dir: config.base_dir,
        options: options,
        allow_empty: record && (cassette_path || yaml_path)
      )
      preflight_session_artifacts!(resolved_outputs, cassette_path, yaml_path,
                                   options: options, input_path: config.path)
      preflight_render_dependencies!(resolved_outputs.map { |_path, format, _output| format })
      raise DependencyError, 'Live sessions are not supported on native Windows' if Gem.win_platform?

      require_relative '../session/runner'
      session = SessionRunner.new(config).run
      write_cassette(cassette_path, session, options) if cassette_path
      write_recording(yaml_path, session, options) if yaml_path
      render_session_outputs(
        session,
        config.outputs,
        base_dir: config.base_dir,
        theme: config.theme,
        render: config.render,
        options: options,
        resolved: resolved_outputs
      )
    end

    def replay_session(options)
      input = @args.shift
      raise ConfigError, 'Cassette file is required' unless input

      session = Cassette.read(input)
      render_session_outputs(session, [], base_dir: Dir.pwd, theme: options.theme || 'macos', render: {},
                                          options: options)
    end

    def render_session_outputs(session, configured_outputs, base_dir:, theme:, render:, options:, resolved: nil)
      resolved ||= resolve_session_outputs(configured_outputs, base_dir: base_dir, options: options)
      resolved.each do |path, format, output|
        ensure_output_writable!(path, options)
        animate = output.fetch(:animate, options.animate || CLI::Generate::ANIMATED_FORMATS.include?(format))
        capture = output[:capture]
        captured_lines = capture && (session.captures[capture] || session.captures[capture.to_sym])
        raise ConfigError, "Unknown capture: #{capture}" if capture && !captured_lines

        config = session.render_config(theme: theme, options: render, animated: animate, lines: captured_lines)
        output_options = CLI::Options.new(**options.to_h.merge(output.slice(:scale, :shadow, :transparent))).freeze
        write_rendered_output(config, path, animate: animate, format: format, options: output_options)
      end
    end

    def resolve_session_outputs(configured_outputs, base_dir:, options:, allow_empty: false)
      outputs = if options.output
                  [{ path: options.output, format: options.format, animate: options.animate }]
                else
                  configured_outputs
                end
      raise ConfigError, 'Output is required with -o or outputs in the session config' if outputs.empty? && !allow_empty

      resolved = outputs.map do |output|
        path = output[:path] == '-' ? '-' : File.expand_path(output[:path], base_dir)
        format = (output[:format] || options.format || File.extname(path).delete_prefix('.')).to_s.downcase
        unless CLI::Generate::SUPPORTED_FORMATS.include?(format)
          raise ValidationError, "format must be one of: #{CLI::Generate::SUPPORTED_FORMATS.join(', ')}"
        end

        animate = if output[:animate].nil?
                    options.animate || CLI::Generate::ANIMATED_FORMATS.include?(format)
                  else
                    output[:animate]
                  end
        validate_output_mode!(format, animate, options)
        raise ConfigError, 'Captured screens cannot be rendered as animations' if output[:capture] && animate

        [path, format, output.merge(animate: animate)]
      end
      duplicate = resolved.group_by(&:first).find { |_path, items| items.size > 1 }&.first
      raise ConfigError, "Multiple outputs resolve to the same path: #{duplicate}" if duplicate

      resolved
    end

    def preflight_session_artifacts!(resolved_outputs, cassette_path, yaml_path, options:, input_path: nil)
      metadata = [cassette_path, yaml_path].compact
      raise ConfigError, 'Cassette and YAML outputs cannot be stdout' if metadata.include?('-')

      paths = resolved_outputs.filter_map { |path, _format, _output| path unless path == '-' } +
              metadata.map { |path| File.expand_path(path) }
      collision = paths.group_by { |path| canonical_output_path(path) }.find { |_path, items| items.size > 1 }&.first
      raise ConfigError, "Session artifacts resolve to the same path: #{collision}" if collision

      canonical_paths = paths.map { |path| canonical_output_path(path) }
      sequence_dirs = resolved_outputs.filter_map do |path, format, _output|
        canonical_output_path(path) if format == 'png-sequence'
      end
      nested = sequence_dirs.find do |directory|
        canonical_paths.any? do |path|
          path != directory && (path_within?(path, directory) || path_within?(directory, path))
        end
      end
      raise ConfigError, "Session artifact conflicts with a PNG sequence directory: #{nested}" if nested
      if input_path && paths.any? { |path| canonical_output_path(path) == canonical_output_path(input_path) }
        raise ConfigError, "Session artifact conflicts with the session configuration: #{input_path}"
      end

      resolved_outputs.each do |path, format, _output|
        if format == 'png-sequence' && Dir.exist?(path) && !replaceable_png_sequence_directory?(path)
          raise FileSystemError, "Refusing to replace a non-Shellfie directory: #{path}"
        end
      end

      paths.each { |path| ensure_output_writable!(path, options) }
      if resolved_outputs.any? do |_path, format, output|
        format == 'mp4' && (options.transparent || output[:transparent])
      end
        raise ConfigError, 'MP4 output does not support transparency'
      end
    end

    def write_cassette(path, session, options)
      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
      if File.exist?(path) && !options.force
        raise FileSystemError, "Cassette already exists: #{path} (use --force to overwrite)"
      end

      Cassette.write(path, session)
      warn "Recorded: #{path}" unless options.quiet
    end

    def write_recording(path, session, options)
      FileUtils.mkdir_p(File.dirname(path)) unless File.dirname(path) == '.'
      if File.exist?(path) && !options.force
        raise FileSystemError, "Recording already exists: #{path} (use --force to overwrite)"
      end

      OutputWriter.write(path, extension: 'yml') do |temporary_path|
        File.write(temporary_path, YAML.dump(session.compose_hash))
      end
      warn "Recorded: #{path}" unless options.quiet
    end
  end
end
