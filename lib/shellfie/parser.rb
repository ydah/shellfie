# frozen_string_literal: true

require "yaml"
require_relative "config"
require_relative "errors"
require_relative "parser_validation"

module Shellfie
  class Parser
    class << self
      include ParserValidation

      def parse(path)
        return parse_string($stdin.read, base_dir: Dir.pwd) if path == "-"
        raise ParseError, "Configuration file not found: #{path}" unless File.exist?(path)

        content = File.read(path)
        parse_string(content, base_dir: File.dirname(path))
      end

      def parse_string(content, base_dir: nil)
        raw = YAML.safe_load(content, symbolize_names: true, aliases: true)
        raw = apply_includes(raw, base_dir) if base_dir
        validate_config(raw)
        build_config(raw)
      rescue Psych::SyntaxError => e
        raise ParseError, "Invalid YAML syntax: #{e.message}"
      end

      private

      def build_config(raw)
        options = {
          version: raw[:version],
          theme: raw[:theme],
          window_theme: raw[:window_theme],
          color_scheme: raw[:color_scheme],
          colors: symbolize_hash(raw[:colors]),
          window_decoration: symbolize_hash(raw[:window_decoration]),
          title: raw[:title],
          window: symbolize_hash(raw[:window]),
          font: symbolize_hash(raw[:font]),
          lines: parse_lines(raw[:lines]),
          animation: symbolize_hash(raw[:animation]),
          cursor: symbolize_hash(raw[:cursor]),
          limits: symbolize_hash(raw[:limits]),
          frames: parse_frames(raw[:frames]),
          headless: raw[:headless] || false
        }.compact

        Config.new(options)
      end

      def apply_includes(raw, base_dir, depth: 0)
        return raw unless raw.is_a?(Hash) && raw[:include]
        raise ParseError, "YAML include depth exceeded" if depth > 5

        includes = Array(raw[:include])
        included_config = includes.reduce({}) do |merged, include_path|
          include_file = File.expand_path(include_path, base_dir)
          raise ParseError, "Included configuration file not found: #{include_path}" unless File.exist?(include_file)

          included_raw = YAML.safe_load(File.read(include_file), symbolize_names: true, aliases: true)
          included_raw = apply_includes(included_raw, File.dirname(include_file), depth: depth + 1)
          deep_merge(merged, included_raw || {})
        end

        deep_merge(included_config, raw.reject { |key, _value| key == :include })
      end

      def deep_merge(base, overrides)
        base.merge(overrides) do |_key, left, right|
          left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
        end
      end

      def symbolize_hash(hash)
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
            delay: frame[:delay] || 0,
            prompt_color: frame[:prompt_color],
            command_color: frame[:command_color],
            output_color: frame[:output_color]
          )
        end
      end
    end
  end

  class Line
    attr_reader :prompt, :command, :output, :prompt_color, :command_color, :output_color, :selected

    def initialize(prompt: nil, command: nil, output: nil, prompt_color: nil, command_color: nil, output_color: nil,
                   selected: false)
      @prompt = prompt
      @command = command
      @output = output
      @prompt_color = prompt_color
      @command_color = command_color
      @output_color = output_color
      @selected = selected
      freeze
    end

    def to_h
      {
        prompt: prompt,
        command: command,
        output: output,
        prompt_color: prompt_color,
        command_color: command_color,
        output_color: output_color,
        selected: selected
      }.compact
    end

    def to_s
      [prompt, command, output].compact.join("\n")
    end
  end

  class Frame
    attr_reader :prompt, :type, :output, :delay, :prompt_color, :command_color, :output_color

    def initialize(prompt: nil, type: nil, output: nil, delay: 0, prompt_color: nil, command_color: nil,
                   output_color: nil)
      @prompt = prompt
      @type = type
      @output = output
      @delay = delay
      @prompt_color = prompt_color
      @command_color = command_color
      @output_color = output_color
      freeze
    end

    def to_h
      {
        prompt: prompt,
        type: type,
        output: output,
        delay: delay,
        prompt_color: prompt_color,
        command_color: command_color,
        output_color: output_color
      }.compact
    end

    def to_s
      [prompt, type, output, delay].compact.join("\n")
    end
  end
end
