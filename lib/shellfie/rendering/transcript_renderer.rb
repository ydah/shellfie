# frozen_string_literal: true

require 'json'
require_relative '../animation/frame_builder'
require_relative '../terminal/ansi_parser'
require_relative '../output_writer'

module Shellfie
  module Rendering
    class TranscriptRenderer
      def initialize(config)
        @config = config
      end

      def render(output_path, format:, io: nil)
        OutputWriter.write(output_path, extension: format, io: io) do |temporary_path|
          value = case format
                  when 'json' then JSON.pretty_generate(document)
                  when 'ansi' then ansi_text
                  when 'asciicast', 'cast' then asciicast
                  else text
                  end
          File.write(temporary_path, value)
        end
      end

    private

      attr_reader :config

      def final_lines
        return config.lines if config.frames.empty?

        Animation::FrameBuilder.new(config).build.last[:lines]
      end

      def text
        final_lines.flat_map do |line|
          command = "#{line.prompt}#{line.command}" if line.prompt || line.command
          [command, line.output].compact.map { |value| plain_text(value) }
        end.join("\n") + "\n"
      end

      def ansi_text
        final_lines.flat_map do |line|
          command = "#{line.prompt}#{line.command}" if line.prompt || line.command
          [command, line.output].compact
        end.join("\n") + "\n"
      end

      def asciicast
        width = [config.window[:width].to_i / 8, 1].max
        header = { version: 2, width: width, height: [final_lines.size, 1].max, env: { 'TERM' => 'xterm-256color' } }
        elapsed = 0.0
        source = if config.frames.empty?
                   [{ text: ansi_text, delay: 0 }]
                 else
                   config.frames.map do |frame|
                     { text: frame_to_ansi(frame), delay: frame.delay }
                   end
                 end
        events = source.map do |event|
          value = [elapsed.round(6), 'o', event[:text]]
          elapsed += event[:delay].to_f / 1_000
          value
        end
        ([JSON.generate(header)] + events.map { |event| JSON.generate(event) }).join("\n") + "\n"
      end

      def frame_to_ansi(frame)
        command = "#{frame.prompt}#{frame.command}" if frame.prompt || frame.command
        "#{[command, frame.output].compact.join("\r\n")}\r\n"
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
        Terminal::ANSIParser.new(state_mode: :line).parse(value.to_s).map(&:text).join
      end
    end
  end
end
