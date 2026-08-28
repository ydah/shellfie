# frozen_string_literal: true

require "json"
require_relative "animation_frame_builder"
require_relative "ansi_parser"
require_relative "output_writer"

module Shellfie
  class TranscriptRenderer
    def initialize(config)
      @config = config
    end

    def render(output_path, format:, io: nil)
      OutputWriter.write(output_path, extension: format, io: io) do |temporary_path|
        File.write(temporary_path, format == "json" ? JSON.pretty_generate(document) : text)
      end
    end

    private

    attr_reader :config

    def final_lines
      return config.lines if config.frames.empty?

      AnimationFrameBuilder.new(config).build.last[:lines]
    end

    def text
      final_lines.flat_map do |line|
        command = "#{line.prompt}#{line.command}" if line.prompt || line.command
        [command, line.output].compact.map { |value| plain_text(value) }
      end.join("\n") + "\n"
    end

    def document
      {
        version: 1,
        title: config.title,
        lines: final_lines.map { |line| plain_value(line.to_h) },
        events: config.frames.map { |frame| plain_value(frame.to_h) }
      }
    end

    def plain_value(value)
      case value
      when String then plain_text(value)
      when Array then value.map { |item| plain_value(item) }
      when Hash then value.transform_values { |item| plain_value(item) }
      else value
      end
    end

    def plain_text(value)
      AnsiParser.new(state_mode: :line).parse(value.to_s).map(&:text).join
    end
  end
end
