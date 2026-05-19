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
        raise ParseError, "Configuration file not found: #{path}" unless File.exist?(path)

        content = File.read(path)
        parse_string(content)
      end

      def parse_string(content)
        raw = YAML.safe_load(content, symbolize_names: true)
        validate_config(raw)
        build_config(raw)
      rescue Psych::SyntaxError => e
        raise ParseError, "Invalid YAML syntax: #{e.message}"
      end

      private

      def build_config(raw)
        options = {
          theme: raw[:theme],
          title: raw[:title],
          window: symbolize_hash(raw[:window]),
          font: symbolize_hash(raw[:font]),
          lines: parse_lines(raw[:lines]),
          animation: symbolize_hash(raw[:animation]),
          cursor: symbolize_hash(raw[:cursor]),
          frames: parse_frames(raw[:frames]),
          headless: raw[:headless] || false
        }.compact

        Config.new(options)
      end

      def symbolize_hash(hash)
        return nil unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym)
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

  Line = Struct.new(
    :prompt,
    :command,
    :output,
    :prompt_color,
    :command_color,
    :output_color,
    :selected,
    keyword_init: true
  )
  Frame = Struct.new(
    :prompt,
    :type,
    :output,
    :delay,
    :prompt_color,
    :command_color,
    :output_color,
    keyword_init: true
  )
end
