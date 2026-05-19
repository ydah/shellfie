# frozen_string_literal: true

require "strscan"

module Shellfie
  module AnsiNormalizer
    ANSI_REGEX = /\e\[([0-9;]*)m/
    OSC_REGEX = /\e\].*?(?:\a|\e\\)/
    CSI_CONTROL_REGEX = /\e\[[0-9;?]*[A-Za-ln-z]/

    module_function

    def normalize(text)
      text = text.gsub(OSC_REGEX, "")
      text = apply_line_controls(text)
      text.gsub(CSI_CONTROL_REGEX, "")
    end

    def apply_line_controls(text)
      buffer = []
      column = 0
      pending_escape = +""
      scanner = StringScanner.new(text)

      until scanner.eos?
        if scanner.scan(ANSI_REGEX)
          pending_escape << scanner.matched
          next
        end

        if scanner.scan(/\e\[[0-9;?]*[JK]/)
          buffer.clear
          column = 0
          next
        end

        if scanner.scan(/\e\[([0-9;?]*)[CDG]/)
          column = apply_cursor_movement(scanner.matched[-1], scanner[1], column)
          next
        end

        column, pending_escape = apply_character(scanner.getch, buffer, column, pending_escape)
      end

      buffer.compact.join + pending_escape
    end

    def apply_character(char, buffer, column, pending_escape)
      case char
      when "\r"
        [0, pending_escape]
      when "\b"
        column = [column - 1, 0].max
        buffer[column] = nil
        [column, pending_escape]
      when "\a"
        [column, pending_escape]
      else
        buffer[column] = "#{pending_escape}#{char}"
        [column + 1, +""]
      end
    end

    def apply_cursor_movement(command, params, column)
      amount = params.to_s.split(";").first.to_i
      amount = 1 if amount <= 0

      case command
      when "C"
        column + amount
      when "D"
        [column - amount, 0].max
      when "G"
        [amount - 1, 0].max
      end
    end
  end
end
