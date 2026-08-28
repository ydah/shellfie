# frozen_string_literal: true

module Shellfie
  module TextMetrics
    module_function

    def graphemes(text)
      text.to_s.scan(/\X/)
    end

    def cell_width(text)
      graphemes(text).sum { |grapheme| grapheme_width(grapheme) }
    end

    def pixel_width(text, font_size)
      (cell_width(text) * font_size * 0.6).ceil
    end

    def take_cells(text, max_cells)
      result = +""
      used_cells = 0

      graphemes(text).each do |char|
        width = grapheme_width(char)
        break if used_cells + width > max_cells

        result << char
        used_cells += width
      end

      result
    end

    def drop_cells(text, cells_to_drop)
      used_cells = 0
      graphemes(text).each_with_object(+"") do |char, result|
        width = grapheme_width(char)
        if used_cells < cells_to_drop
          used_cells += width
          next
        end

        result << char
      end
    end

    def split_cells(text, max_cells)
      return [text.to_s] if max_cells <= 0

      chunks = []
      current = +""
      used_cells = 0

      graphemes(text).each do |char|
        width = grapheme_width(char)
        if used_cells.positive? && used_cells + width > max_cells
          chunks << current
          current = +""
          used_cells = 0
        end

        current << char
        used_cells += width
      end

      chunks << current unless current.empty?
      chunks
    end

    def char_width(char)
      codepoint = char.ord
      return 0 if combining?(codepoint)
      return 0 if codepoint < 32 || codepoint == 0x7f
      return 2 if wide?(codepoint)

      1
    end

    def grapheme_width(grapheme)
      codepoints = grapheme.codepoints
      return 0 if codepoints.empty? || codepoints.all? { |codepoint| combining?(codepoint) }
      return 2 if grapheme.include?("\u200d") || grapheme.match?(/[\u{1f1e6}-\u{1f1ff}]{2}/)

      codepoints.map { |codepoint| char_width(codepoint.chr(Encoding::UTF_8)) }.max || 0
    end

    def combining?(codepoint)
      (0x0300..0x036f).cover?(codepoint) ||
        (0x1ab0..0x1aff).cover?(codepoint) ||
        (0x1dc0..0x1dff).cover?(codepoint) ||
        (0x20d0..0x20ff).cover?(codepoint) ||
        (0xfe20..0xfe2f).cover?(codepoint)
    end

    def wide?(codepoint)
      (0x1100..0x115f).cover?(codepoint) ||
        (0x2329..0x232a).cover?(codepoint) ||
        (0x2e80..0xa4cf).cover?(codepoint) ||
        (0xac00..0xd7a3).cover?(codepoint) ||
        (0xf900..0xfaff).cover?(codepoint) ||
        (0xfe10..0xfe19).cover?(codepoint) ||
        (0xfe30..0xfe6f).cover?(codepoint) ||
        (0xff00..0xff60).cover?(codepoint) ||
        (0xffe0..0xffe6).cover?(codepoint) ||
        (0x1f300..0x1faff).cover?(codepoint)
    end
  end
end
