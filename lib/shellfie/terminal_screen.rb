# frozen_string_literal: true

require_relative "text_metrics"

module Shellfie
  class TerminalScreen
    CSI = /\A\e\[([0-9;?]*)([ -\/]*)?([@-~])\z/
    TOKENS = /\e\].*?(?:\a|\e\\)|\e\[[0-9;?]*[ -\/]*[@-~]|\e[78DEM]|[\r\n\b\t\a]|\X/m
    CONTINUATION = Object.new.freeze

    attr_reader :row, :column, :rows, :columns

    def initialize(columns: 80, rows: 24, tab_width: 8)
      @columns = columns
      @rows = rows
      @tab_width = tab_width
      @cells = Array.new(rows) { Array.new(columns) }
      @row = 0
      @column = 0
      @saved_cursor = [0, 0]
      @scroll_top = 0
      @scroll_bottom = rows - 1
      @primary_state = nil
    end

    def feed(text)
      text.to_s.scan(TOKENS).each { |token| process(token) }
      self
    end

    def lines
      @cells.map { |cells| cells.reject { |cell| cell.equal?(CONTINUATION) }.map { |cell| cell || " " }.join.rstrip }
            .then { |all| all[0..(all.rindex { |line| !line.empty? } || 0)] }
    end

    def to_s
      lines.join("\n")
    end

    private

    def process(token)
      return if token.start_with?("\e]")
      match = CSI.match(token)
      return process_csi(match[1], match[3]) if match

      case token
      when "\r" then @column = 0
      when "\n" then newline
      when "\b" then @column = [@column - 1, 0].max
      when "\t" then (@tab_width - (@column % @tab_width)).times { write(" ") }
      when "\a" then nil
      when "\e7" then @saved_cursor = [@row, @column]
      when "\e8" then @row, @column = @saved_cursor
      when "\eD" then newline
      when "\eE" then newline
      when "\eM" then reverse_index
      else write(token)
      end
    end

    def process_csi(params, command)
      private_mode = params.start_with?("?")
      values = params.delete_prefix("?").split(";").map { |value| Integer(value, exception: false) || 0 }
      amount = values.first.to_i.positive? ? values.first : 1
      case command
      when "A" then @row = [@row - amount, 0].max
      when "B" then @row = [@row + amount, @rows - 1].min
      when "C" then @column = [@column + amount, @columns - 1].min
      when "D" then @column = [@column - amount, 0].max
      when "E" then @row = [@row + amount, @rows - 1].min; @column = 0
      when "F" then @row = [@row - amount, 0].max; @column = 0
      when "G" then @column = [[amount - 1, 0].max, @columns - 1].min
      when "H", "f" then position(values)
      when "J" then erase_display(values.first || 0)
      when "K" then erase_line(values.first || 0)
      when "@" then insert_characters(amount)
      when "P" then delete_characters(amount)
      when "L" then insert_lines(amount)
      when "M" then delete_lines(amount)
      when "s" then @saved_cursor = [@row, @column]
      when "u" then @row, @column = @saved_cursor
      when "r" then set_scroll_region(values)
      when "h" then enter_alternate_screen if private_mode && (values & [47, 1047, 1049]).any?
      when "l" then leave_alternate_screen if private_mode && (values & [47, 1047, 1049]).any?
      end
    end

    def write(grapheme)
      width = TextMetrics.grapheme_width(grapheme)
      return if width.zero?
      newline if @column + width > @columns

      clear_wide_cell(@row, @column)
      @cells[@row][@column] = grapheme
      @cells[@row][@column + 1] = CONTINUATION if width == 2 && @column + 1 < @columns
      @column += width
      newline if @column >= @columns
    end

    def newline
      if @row == @scroll_bottom
        @cells.delete_at(@scroll_top)
        @cells.insert(@scroll_bottom, Array.new(@columns))
        @column = 0
        return
      end

      @row += 1
      @column = 0
      return if @row < @rows

      @cells.shift
      @cells << Array.new(@columns)
      @row = @rows - 1
    end

    def reverse_index
      if @row == @scroll_top
        @cells.insert(@scroll_top, Array.new(@columns))
        @cells.delete_at(@scroll_bottom + 1)
      else
        @row = [@row - 1, 0].max
      end
    end

    def set_scroll_region(values)
      top = (values[0].to_i.nonzero? || 1) - 1
      bottom = (values[1].to_i.nonzero? || @rows) - 1
      return unless top.between?(0, @rows - 1) && bottom.between?(0, @rows - 1) && top < bottom

      @scroll_top = top
      @scroll_bottom = bottom
      @row = 0
      @column = 0
    end

    def enter_alternate_screen
      return if @primary_state

      @primary_state = [@cells, @row, @column, @saved_cursor, @scroll_top, @scroll_bottom]
      @cells = Array.new(@rows) { Array.new(@columns) }
      @row = @column = @scroll_top = 0
      @scroll_bottom = @rows - 1
      @saved_cursor = [0, 0]
    end

    def leave_alternate_screen
      return unless @primary_state

      @cells, @row, @column, @saved_cursor, @scroll_top, @scroll_bottom = @primary_state
      @primary_state = nil
    end

    def position(values)
      @row = [[(values[0].to_i.nonzero? || 1) - 1, 0].max, @rows - 1].min
      @column = [[(values[1].to_i.nonzero? || 1) - 1, 0].max, @columns - 1].min
    end

    def erase_display(mode)
      case mode
      when 1
        (0...@row).each { |index| @cells[index] = Array.new(@columns) }
        @cells[@row][0..@column] = Array.new(@column + 1)
      when 2, 3
        @cells = Array.new(@rows) { Array.new(@columns) }
      else
        erase_line(0)
        (@row + 1...@rows).each { |index| @cells[index] = Array.new(@columns) }
      end
    end

    def erase_line(mode)
      range = case mode
              when 1 then 0..@column
              when 2 then 0...@columns
              else @column...@columns
              end
      range.each { |index| @cells[@row][index] = nil }
    end

    def insert_characters(amount)
      amount.times { @cells[@row].insert(@column, nil) }
      @cells[@row] = @cells[@row].first(@columns)
    end

    def delete_characters(amount)
      @cells[@row].slice!(@column, amount)
      @cells[@row].concat(Array.new(amount)).slice!(@columns..)
    end

    def insert_lines(amount)
      amount.times { @cells.insert(@row, Array.new(@columns)) }
      @cells = @cells.first(@rows)
    end

    def delete_lines(amount)
      @cells.slice!(@row, amount)
      @cells.concat(Array.new(amount) { Array.new(@columns) }).slice!(@rows..)
    end

    def clear_wide_cell(row, column)
      @cells[row][column - 1] = nil if column.positive? && @cells[row][column].equal?(CONTINUATION)
      @cells[row][column + 1] = nil if @cells[row][column + 1].equal?(CONTINUATION)
    end
  end
end
