# frozen_string_literal: true

require "json"
require_relative "animation_frame_builder"
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
        [command, line.output].compact
      end.join("\n") + "\n"
    end

    def document
      {
        version: 1,
        title: config.title,
        lines: final_lines.map(&:to_h),
        events: config.frames.map(&:to_h)
      }
    end
  end
end
