# frozen_string_literal: true

require "yaml"
require_relative "config"
require_relative "errors"

module Shellfie
  class Parser
    class << self
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

      def validate_config(raw)
        raise ValidationError, "Empty configuration" if raw.nil? || raw.empty?

        valid_themes = %w[macos ubuntu windows]
        if raw[:theme] && !valid_themes.include?(raw[:theme])
          raise ValidationError, "Invalid theme '#{raw[:theme]}'\n  → Available themes: #{valid_themes.join(", ")}"
        end

        if raw[:lines].nil? && raw[:frames].nil?
          raise ValidationError, "Configuration must have either 'lines' or 'frames'"
        end
      end

      def build_config(raw)
        options = {
          theme: raw[:theme],
          title: raw[:title],
          window: symbolize_hash(raw[:window]),
          font: symbolize_hash(raw[:font]),
          lines: parse_lines(raw[:lines]),
          animation: symbolize_hash(raw[:animation]),
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
        return [] unless lines.is_a?(Array)

        lines.map do |line|
          Line.new(
            prompt: line[:prompt],
            command: line[:command],
            output: line[:output]
          )
        end
      end

      def parse_frames(frames)
        return [] unless frames.is_a?(Array)

        frames.map do |frame|
          Frame.new(
            prompt: frame[:prompt],
            type: frame[:type],
            output: frame[:output],
            delay: frame[:delay] || 0
          )
        end
      end
    end
  end

  Line = Struct.new(:prompt, :command, :output, keyword_init: true)
  Frame = Struct.new(:prompt, :type, :output, :delay, keyword_init: true)
end
