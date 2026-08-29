# frozen_string_literal: true

require_relative "text_metrics"
require_relative "ansi_parser"

module Shellfie
  class TerminalScreen
    CSI = /\A\e\[([0-9;:?]*)([ -\/]*)?([@-~])\z/
    STRING_CONTROL = /\e(?:\]|P|_|\^).*?(?:\a|\e\\)/m
    TOKENS = /#{STRING_CONTROL}|\e\[[0-9;:?]*[ -\/]*[@-~]|\e[78DEM]|[\r\n\b\t\a]|\X/m
    MAX_PENDING_CONTROL_BYTES = 1_048_576
    CONTINUATION = Object.new.freeze

    attr_reader :row, :column, :rows, :columns

    def initialize(columns: 80, rows: 24, tab_width: 8, graphics_policy: "ignore")
      @columns = columns
      @rows = rows
      @tab_width = tab_width
      @graphics_policy = graphics_policy
      @cells = Array.new(rows) { Array.new(columns) }
      @row = 0
      @column = 0
      @saved_cursor = [0, 0]
      @scroll_top = 0
      @scroll_bottom = rows - 1
      @primary_state = nil
      @pending_control = +""
      @discarding_control = nil
      @discard_control_tail = +""
      @wrap_pending = false
      @ansi_parser = AnsiParser.new
    end

    def feed(text)
      input = discard_control_prefix(text.to_s)
      return self if input.empty? && @discarding_control

      input = @pending_control << input
      if @graphics_policy == "error" && input.match?(AnsiNormalizer::GRAPHICS_CONTROL_PREFIX)
        raise ValidationError, "Terminal graphics are not supported; use window.graphics_policy: ignore to discard them"
      end
      input, @pending_control = split_incomplete_control(input)
      input.scan(TOKENS).each { |token| process(token) }
      self
    end

    def lines
      visible_rows.map { |cells| cells.reject { |cell| cell.equal?(CONTINUATION) }.map { |cell| cell&.text || " " }.join.rstrip }
    end

    def render_lines
      visible_rows.map do |cells|
        visible = cells.reject { |cell| cell.equal?(CONTINUATION) }
        last = visible.rindex { |cell| cell && cell.text != " " }
        next "" unless last

        visible[0..last].chunk { |cell| style_key(cell) }.map do |_style, group|
          cells_in_style = group.to_a
          text = cells_in_style.map { |cell| cell&.text || " " }.join
          styled_cell(cells_in_style.first, text)
        end.join
      end
    end

    def to_s
      lines.join("\n")
    end

    private

    def process(token)
      return if token.match?(/\A\e(?:\]|P|_|\^)/)
      match = CSI.match(token)
      @ansi_parser.parse(token) if match && match[3] == "m"
      if match
        @wrap_pending = false unless match[3] == "m"
        return process_csi(match[1], match[3])
      end

      case token
      when "\r" then @column = 0; @wrap_pending = false
      when "\n" then newline(reset_column: false)
      when "\b" then @column = [@column - 1, 0].max; @wrap_pending = false
      when "\t"
        @column = [@column + @tab_width - (@column % @tab_width), @columns - 1].min
        @wrap_pending = false
      when "\a" then nil
      when "\e7" then @saved_cursor = [@row, @column]
      when "\e8" then @row, @column = @saved_cursor
      when "\eD" then newline(reset_column: false)
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
      return if extend_previous_grapheme(grapheme)

      width = TextMetrics.grapheme_width(grapheme)
      return if width.zero?
      newline if @wrap_pending
      newline if @column + width > @columns

      clear_wide_cell(@row, @column)
      @cells[@row][@column] = @ansi_parser.parse(grapheme).first
      @cells[@row][@column + 1] = CONTINUATION if width == 2 && @column + 1 < @columns
      @column += width
      if @column >= @columns
        @column = @columns - 1
        @wrap_pending = true
      end
    end

    def extend_previous_grapheme(grapheme)
      return false if @column.zero?

      owner_column = @wrap_pending ? @column : @column - 1
      owner_column -= 1 if @cells[@row][owner_column].equal?(CONTINUATION)
      owner = @cells[@row][owner_column]
      return false unless owner && TextMetrics.graphemes(owner.text + grapheme).size == 1

      old_width = TextMetrics.grapheme_width(owner.text)
      owner.text << grapheme
      new_width = TextMetrics.grapheme_width(owner.text)
      if old_width == 1 && new_width == 2 && owner_column + 1 < @columns
        @cells[@row][owner_column + 1] = CONTINUATION
        @column += 1
        if @column >= @columns
          @column = @columns - 1
          @wrap_pending = true
        end
      end
      true
    end

    def newline(reset_column: true)
      @wrap_pending = false
      if @row == @scroll_bottom
        @cells.delete_at(@scroll_top)
        @cells.insert(@scroll_bottom, Array.new(@columns))
        @column = 0 if reset_column
        return
      end

      if @row == @rows - 1
        @column = 0 if reset_column
        return
      end

      @row += 1
      @column = 0 if reset_column
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

      @primary_state = [@cells, @row, @column, @saved_cursor, @scroll_top, @scroll_bottom, @wrap_pending]
      @cells = Array.new(@rows) { Array.new(@columns) }
      @row = @column = @scroll_top = 0
      @wrap_pending = false
      @scroll_bottom = @rows - 1
      @saved_cursor = [0, 0]
    end

    def leave_alternate_screen
      return unless @primary_state

      @cells, @row, @column, @saved_cursor, @scroll_top, @scroll_bottom, @wrap_pending = @primary_state
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
        erase_line(1)
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
      range.each do |index|
        clear_wide_cell(@row, index)
        @cells[@row][index] = nil
      end
    end

    def insert_characters(amount)
      clear_wide_cell(@row, @column)
      amount.times { @cells[@row].insert(@column, nil) }
      @cells[@row] = @cells[@row].first(@columns)
      repair_wide_cells(@row)
    end

    def delete_characters(amount)
      (@column...[@column + amount, @columns].min).each { |index| clear_wide_cell(@row, index) }
      @cells[@row].slice!(@column, amount)
      @cells[@row].concat(Array.new(amount)).slice!(@columns..)
      repair_wide_cells(@row)
    end

    def insert_lines(amount)
      return unless @row.between?(@scroll_top, @scroll_bottom)

      [amount, @scroll_bottom - @row + 1].min.times do
        @cells.insert(@row, Array.new(@columns))
        @cells.delete_at(@scroll_bottom + 1)
      end
    end

    def delete_lines(amount)
      return unless @row.between?(@scroll_top, @scroll_bottom)

      [amount, @scroll_bottom - @row + 1].min.times do
        @cells.delete_at(@row)
        @cells.insert(@scroll_bottom, Array.new(@columns))
      end
    end

    def clear_wide_cell(row, column)
      @cells[row][column - 1] = nil if column.positive? && @cells[row][column].equal?(CONTINUATION)
      @cells[row][column + 1] = nil if @cells[row][column + 1].equal?(CONTINUATION)
    end

    def repair_wide_cells(row)
      @cells[row].each_with_index do |cell, column|
        if cell.equal?(CONTINUATION)
          owner = column.positive? && @cells[row][column - 1]
          @cells[row][column] = nil unless owner && TextMetrics.grapheme_width(owner.text) == 2
        elsif cell && TextMetrics.grapheme_width(cell.text) == 2 && !@cells[row][column + 1].equal?(CONTINUATION)
          @cells[row][column] = nil
        end
      end
    end

    def split_incomplete_control(text)
      starts = ["\e]", "\eP", "\e_", "\e^"].filter_map { |prefix| text.rindex(prefix) }
      if (start = starts.max) && !text[start..].match?(/\A#{STRING_CONTROL}/)
        tail = text[start..]
        if tail.bytesize > MAX_PENDING_CONTROL_BYTES
          @discarding_control = :string
          return [text[0...start], +""]
        end
        return [text[0...start], tail]
      end
      if (start = text.rindex("\e[")) && text[start..].match?(/\A\e\[[0-9;:?]*[ -\/]*\z/)
        tail = text[start..]
        if tail.bytesize > MAX_PENDING_CONTROL_BYTES
          @discarding_control = :csi
          return [text[0...start], +""]
        end
        return [text[0...start], tail]
      end
      return [text[0...-1], "\e"] if text.end_with?("\e")

      [text, +""]
    end

    def discard_control_prefix(text)
      return text unless @discarding_control

      text = @discard_control_tail << text
      @discard_control_tail = +""
      finish = if @discarding_control == :csi
                 final = text.index(/[@-~]/)
                 final && final + 1
               else
                 bell = text.index("\a")
                 st = text.index("\e\\")
                 [bell && bell + 1, st && st + 2].compact.min
               end
      unless finish
        @discard_control_tail = +"\e" if @discarding_control == :string && text.end_with?("\e")
        return ""
      end

      @discarding_control = nil
      text[finish..].to_s
    end

    def visible_rows
      last = @cells.rindex { |cells| cells.any? { |cell| cell && !cell.equal?(CONTINUATION) } } || 0
      @cells[0..last]
    end

    def styled_cell(cell, text = cell&.text || " ")
      return text unless cell

      codes = []
      codes << 1 if cell.bold
      codes << 2 if cell.dim
      codes << 3 if cell.italic
      if cell.underline
        underline_code = { double: 21, curly: "4:3", dotted: "4:4", dashed: "4:5" }.fetch(cell.underline_style, 4)
        codes << underline_code
      end
      codes.concat(color_codes(cell.underline_color, 58)) if cell.underline_color
      codes << 5 if cell.blink
      codes << 8 if cell.conceal
      codes << 7 if cell.reverse
      codes << 9 if cell.strikethrough
      codes << 53 if cell.overline
      codes.concat(color_codes(cell.foreground, 38)) if cell.foreground
      codes.concat(color_codes(cell.background, 48)) if cell.background
      return text if codes.empty?

      "\e[#{codes.join(";")}m#{text}\e[0m"
    end

    def style_key(cell)
      return nil unless cell

      [cell.foreground, cell.background, cell.bold, cell.italic, cell.underline, cell.underline_style,
       cell.underline_color, cell.dim, cell.reverse, cell.strikethrough, cell.overline, cell.blink, cell.conceal]
    end

    def color_codes(color, prefix)
      standard = prefix == 38 ? AnsiColors::COLORS.key(color) : AnsiColors::BG_COLORS.key(color)
      return [standard] if standard
      return [] unless color.match?(/\A#[0-9a-fA-F]{6}\z/)

      [prefix, 2, color[1, 2].to_i(16), color[3, 2].to_i(16), color[5, 2].to_i(16)]
    end
  end
end
