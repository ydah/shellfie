# frozen_string_literal: true

require "strscan"
require_relative "ansi_line_buffer"

module Shellfie
  module AnsiNormalizer
    ANSI_REGEX = /\e\[([0-9;]*)m/
    OSC_REGEX = /\e\].*?(?:\a|\e\\)/
    CSI_CONTROL_REGEX = /\e\[[0-9;?]*[A-Za-ln-z]/

    module_function

    def normalize(text, tab_width: 8)
      text = TextMetrics.graphemes(text).join
      text = text.gsub(OSC_REGEX, "")
      text = apply_line_controls(text, tab_width: tab_width)
      text.gsub(CSI_CONTROL_REGEX, "")
    end

    def apply_line_controls(text, tab_width: 8)
      buffer = AnsiLineBuffer.new(tab_width: tab_width)
      scanner = StringScanner.new(text)

      until scanner.eos?
        if scanner.scan(ANSI_REGEX)
          buffer.write_escape(scanner.matched)
          next
        end

        if scanner.scan(/\e\[([0-9;?]*)[JK]/)
          buffer.clear(scanner.matched[-1], scanner[1])
          next
        end

        if scanner.scan(/\e\[([0-9;?]*)[CDG]/)
          buffer.move(scanner.matched[-1], scanner[1])
          next
        end

        if scanner.scan(/\e\[([0-9;?]*)[Hf]/)
          buffer.position(scanner[1])
          next
        end

        buffer.write_character(scanner.scan(/\X/))
      end

      buffer.to_s
    end
  end
end
