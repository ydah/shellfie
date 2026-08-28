# frozen_string_literal: true

require_relative "text_metrics"

module Shellfie
  class AnsiLineBuffer
    CONTINUATION = Object.new.freeze

    def initialize(tab_width: 8)
      @cells = []
      @column = 0
      @pending_escape = +""
      @tab_width = tab_width
    end

    def write_escape(sequence)
      @pending_escape << sequence
    end

    def write_character(char)
      case char
      when "\r"
        @column = 0
      when "\b"
        @column = [@column - 1, 0].max
      when "\t"
        (@tab_width - (@column % @tab_width)).times { write_character(" ") }
      when "\a"
        nil
      else
        width = TextMetrics.grapheme_width(char)
        return if width.zero?

        clear_wide_cell(@column)
        @cells[@column] = "#{@pending_escape}#{char}"
        @cells[@column + 1] = CONTINUATION if width == 2
        @pending_escape = +""
        @column += width
      end
    end

    def move(command, params)
      amount = first_param(params, default: 1)
      case command
      when "C"
        @column += amount
      when "D"
        @column = [@column - amount, 0].max
      when "G"
        @column = [amount - 1, 0].max
      end
    end

    def position(params)
      values = params.to_s.split(";")
      column = values.length >= 2 ? Integer(values[1], exception: false) : 1
      @column = [[column || 1, 1].max - 1, 0].max
    end

    def clear(command, params)
      mode = first_param(params, default: 0)
      command == "K" ? clear_line(mode) : clear_screen(mode)
    end

    def to_s
      last = @cells.rindex { |cell| !cell.nil? }
      return @pending_escape unless last

      @cells[0..last].map { |cell| cell.equal?(CONTINUATION) ? "" : (cell || " ") }.join + @pending_escape
    end

    private

    def first_param(params, default:)
      value = Integer(params.to_s.split(";").first, exception: false)
      value && value.positive? ? value : default
    end

    def clear_line(mode)
      case mode
      when 1
        clear_range(0..@column)
      when 2, 3
        @cells.clear
      else
        @cells.slice!(@column..)
      end
    end

    def clear_screen(mode)
      mode.zero? ? clear_line(0) : clear_line(2)
    end

    def clear_range(range)
      range.each { |index| @cells[index] = nil if index < @cells.length }
    end

    def clear_wide_cell(column)
      @cells[column - 1] = nil if column.positive? && @cells[column].equal?(CONTINUATION)
      @cells[column + 1] = nil if @cells[column + 1].equal?(CONTINUATION)
    end
  end
end
