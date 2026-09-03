# frozen_string_literal: true

require 'yaml'
require_relative 'config'
require_relative 'errors'
require_relative 'frame'
require_relative 'line'
require_relative 'parser/validates_input'
require_relative 'yaml_safety'

module Shellfie
  class Parser
    MAX_INCLUDE_BYTES = 1_048_576
    MAX_INCLUDE_DEPTH = 50
    MAX_INCLUDE_FILES = 100
    MAX_TOTAL_INCLUDE_BYTES = 10 * MAX_INCLUDE_BYTES

    class << self
      include ValidatesInput

      def parse(path)
        return parse_string($stdin.read(MAX_INCLUDE_BYTES + 1), base_dir: Dir.pwd) if path == '-'

        source_path = File.realpath(path)
        content = read_config(source_path)
        state = { files: 1, bytes: content.bytesize, cache: {}, sources: {} }
        parse_string(content, base_dir: File.dirname(source_path), include_stack: [source_path], source_name: source_path,
                              include_state: state)
      rescue Errno::ENOENT
        raise ParseError, "Configuration file not found: #{path}"
      end

      def parse_string(content, base_dir: nil, include_stack: [], source_name: nil, include_state: nil)
        if content.bytesize > MAX_INCLUDE_BYTES
          raise ParseError,
                "Configuration is too large (max #{MAX_INCLUDE_BYTES} bytes)"
        end

        raw = YAML.safe_load(content, symbolize_names: true, aliases: true)
        YAMLSafety.validate_tree(raw)
        if base_dir
          include_state ||= { files: 1, bytes: content.bytesize, cache: {}, sources: {} }
          raw = apply_includes(raw, base_dir, stack: include_stack, root: base_dir, state: include_state)
        end
        validate_config(raw)
        sources = (include_stack + Array(include_state&.dig(:cache)&.keys)).uniq
        build_config(raw, source_paths: sources)
      rescue Psych::Exception => e
        raise ParseError, "Invalid YAML syntax: #{e.message}"
      rescue ValidationError => e
        raise e unless source_name

        documents = [[source_name, content]] + include_state.fetch(:sources, {}).to_a.reverse
        raise YAMLSafety.annotate_validation_error(e, documents)
      end

      private

      def build_config(raw, source_paths: [])
        options = {
          version: raw[:version],
          theme: raw[:theme],
          window_theme: raw[:window_theme],
          color_scheme: raw[:color_scheme],
          colors: symbolize_keys(raw[:colors]),
          window_decoration: symbolize_keys(raw[:window_decoration]),
          title: raw[:title],
          window: symbolize_keys(raw[:window]),
          font: symbolize_keys(raw[:font]),
          lines: parse_lines(raw[:lines]),
          animation: symbolize_keys(raw[:animation]),
          cursor: symbolize_keys(raw[:cursor]),
          limits: symbolize_keys(raw[:limits]),
          frames: parse_frames(raw[:frames]),
          headless: raw[:headless] || false,
          source_paths: source_paths
        }.compact

        Config.new(options)
      end

      def apply_includes(raw, base_dir, state:, stack: [], root: base_dir, policy: nil, depth: 0)
        return raw unless raw.is_a?(Hash) && raw[:include]
        raise ParseError, "YAML include depth exceeds #{MAX_INCLUDE_DEPTH}" if depth >= MAX_INCLUDE_DEPTH

        policy ||= raw[:include_policy] || 'allow'
        raise ParseError, 'include_policy must be allow or root' unless %w[allow root].include?(policy)

        included_config = Array(raw[:include]).reduce({}) do |merged, include_path|
          deep_merge(merged, load_include(include_path, base_dir, root: root, policy: policy, stack: stack,
                                                                  state: state, depth: depth))
        end

        deep_merge(included_config, raw.except(:include))
      end

      def load_include(include_path, base_dir, root:, policy:, stack:, state:, depth:)
        include_file = resolve_include(include_path, base_dir, root: root, policy: policy)
        validate_include_chain(include_file, stack)
        track_include(state)
        included_raw = fetch_include(include_file, state)
        apply_includes(
          included_raw,
          File.dirname(include_file),
          stack: stack + [include_file],
          root: root,
          policy: policy,
          state: state,
          depth: depth + 1
        ) || {}
      end

      def resolve_include(include_path, base_dir, root:, policy:)
        raise ParseError, 'Included configuration path must be a string' unless include_path.is_a?(String)

        include_file = File.expand_path(include_path, base_dir)
        raise ParseError, "Included configuration file not found: #{include_path}" unless File.exist?(include_file)

        include_file = File.realpath(include_file)
        if policy == 'root' && include_file != root && !include_file.start_with?("#{root}#{File::SEPARATOR}")
          raise ParseError, "Included configuration escapes the configuration root: #{include_path}"
        end

        include_file
      end

      def validate_include_chain(include_file, stack)
        return unless stack.include?(include_file)

        chain = (stack + [include_file]).map { |path| File.basename(path) }.join(' -> ')
        raise ParseError, "Circular YAML include: #{chain}"
      end

      def track_include(state)
        state[:files] += 1
        return if state[:files] <= MAX_INCLUDE_FILES

        raise ParseError, "Too many YAML includes (max #{MAX_INCLUDE_FILES})"
      end

      def fetch_include(include_file, state)
        return state[:cache][include_file] if state[:cache][include_file]

        content = read_config(include_file)
        state[:sources][include_file] = content
        state[:bytes] += content.bytesize
        if state[:bytes] > MAX_TOTAL_INCLUDE_BYTES
          raise ParseError, "Included YAML is too large in total (max #{MAX_TOTAL_INCLUDE_BYTES} bytes)"
        end

        YAML.safe_load(content, symbolize_names: true, aliases: true).tap do |included_raw|
          YAMLSafety.validate_tree(included_raw)
          state[:cache][include_file] = included_raw
        end
      end

      def read_config(path)
        YAMLSafety.read_file(path, max_bytes: MAX_INCLUDE_BYTES)
      end

      def deep_merge(base, overrides)
        base.merge(overrides) do |_key, left, right|
          left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
        end
      end

      def symbolize_keys(hash)
        return nil unless hash.is_a?(Hash)

        Config.normalize_keys(hash)
      end

      def parse_lines(lines)
        return [] if lines.nil?

        lines.map do |line|
          Line.new(
            prompt: line[:prompt],
            command: line[:command],
            output: line[:output],
            prompt_color: line[:prompt_color],
            command_color: line[:command_color],
            output_color: line[:output_color],
            selected: line[:selected] || false
          )
        end
      end

      def parse_frames(frames)
        return [] if frames.nil?

        frames.map do |frame|
          Frame.new(
            prompt: frame[:prompt],
            type: frame[:type],
            output: frame[:output],
            screen: frame[:screen],
            delay: frame[:delay] || 0,
            prompt_color: frame[:prompt_color],
            command_color: frame[:command_color],
            output_color: frame[:output_color]
          )
        end
      end
    end
  end
end
