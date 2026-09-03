# frozen_string_literal: true

require 'rbconfig'

module Shellfie
  module Terminal
    module TextMetrics
      UNICODE_VERSION = RbConfig::CONFIG['UNICODE_VERSION'] || 'unknown'
      WIDTH_TABLE_VERSION = '1'
      AMBIGUOUS_RANGES = [
        0x00a1..0x00a1, 0x00a4..0x00a4, 0x00a7..0x00a8, 0x00aa..0x00aa, 0x00ad..0x00ae,
        0x00b0..0x00b4, 0x00b6..0x00ba, 0x00bc..0x00bf, 0x00c6..0x00c6, 0x00d0..0x00d0,
        0x00d7..0x00d8, 0x00de..0x00e1, 0x00e6..0x00e6, 0x00e8..0x00ea, 0x00ec..0x00ed,
        0x00f0..0x00f0, 0x00f2..0x00f3, 0x00f7..0x00fa, 0x00fc..0x00fc, 0x00fe..0x00fe,
        0x0101..0x0101, 0x0111..0x0113, 0x011b..0x011b, 0x0126..0x0127, 0x012b..0x012b,
        0x0131..0x0133, 0x0138..0x0138, 0x013f..0x0142, 0x0144..0x0144, 0x0148..0x014b,
        0x014d..0x014d, 0x0152..0x0153, 0x0166..0x0167, 0x016b..0x016b, 0x01ce..0x01dc,
        0x0251..0x0251, 0x0261..0x0261, 0x02c4..0x02c4, 0x02c7..0x02c7, 0x02c9..0x02cb,
        0x02cd..0x02d0, 0x02d8..0x02db, 0x02dd..0x02df, 0x0391..0x03a1, 0x03a3..0x03a9,
        0x03b1..0x03c1, 0x03c3..0x03c9, 0x0401..0x0401, 0x0410..0x044f, 0x0451..0x0451,
        0x2010..0x2010, 0x2013..0x2016, 0x2018..0x2019, 0x201c..0x201d, 0x2020..0x2022,
        0x2024..0x2026, 0x2030..0x2030, 0x2032..0x2033, 0x2035..0x2035, 0x203b..0x203e,
        0x2074..0x2074, 0x207f..0x207f, 0x2081..0x2084, 0x20ac..0x20ac, 0x2103..0x2103,
        0x2105..0x2105, 0x2109..0x2109, 0x2113..0x2113, 0x2116..0x2116, 0x2121..0x2122,
        0x2126..0x2126, 0x212b..0x212b, 0x2153..0x2154, 0x215b..0x215e, 0x2160..0x216b,
        0x2170..0x2179, 0x2189..0x2189, 0x2190..0x2199, 0x21b8..0x21b9, 0x21d2..0x21d4,
        0x21e7..0x21e7, 0x2200..0x2200, 0x2202..0x2203, 0x2207..0x2208, 0x220b..0x220b,
        0x220f..0x2211, 0x2215..0x2215, 0x221a..0x221a, 0x221d..0x2220, 0x2223..0x2223,
        0x2225..0x2225, 0x2227..0x222c, 0x222e..0x222e, 0x2234..0x2237, 0x223c..0x223d,
        0x2248..0x2248, 0x224c..0x224c, 0x2252..0x2252, 0x2260..0x2261, 0x2264..0x2267,
        0x226a..0x226b, 0x226e..0x226f, 0x2282..0x2283, 0x2286..0x2287, 0x2295..0x2295,
        0x2299..0x2299, 0x22a5..0x22a5, 0x22bf..0x22bf, 0x2312..0x2312, 0x2460..0x254b,
        0x2550..0x2573, 0x2580..0x258f, 0x2592..0x2595, 0x25a0..0x25a1, 0x25a3..0x25a9,
        0x25b2..0x25b3, 0x25b6..0x25b7, 0x25bc..0x25bd, 0x25c0..0x25c1, 0x25c6..0x25c8,
        0x25cb..0x25cb, 0x25ce..0x25d1, 0x25e2..0x25e5, 0x25ef..0x25ef, 0x2605..0x2606,
        0x2609..0x2609, 0x260e..0x260f, 0x261c..0x261c, 0x261e..0x261e, 0x2640..0x2640,
        0x2642..0x2642, 0x2660..0x2661, 0x2663..0x2665, 0x2667..0x266a, 0x266c..0x266d,
        0x266f..0x266f, 0xe000..0xf8ff, 0xfffd..0xfffd
      ].freeze

    module_function

      def graphemes(text)
        string = text.to_s.dup
        string.force_encoding(Encoding::UTF_8)
        string.scrub.scan(/\X/)
      end

      def cell_width(text, ambiguous_width: 1)
        graphemes(text).sum { |grapheme| grapheme_width(grapheme, ambiguous_width: ambiguous_width) }
      end

      def pixel_width(text, font_size, ambiguous_width: 1)
        (cell_width(text, ambiguous_width: ambiguous_width) * font_size * 0.6).ceil
      end

      def take_cells(text, max_cells, ambiguous_width: 1)
        result = +''
        used_cells = 0

        graphemes(text).each do |char|
          width = grapheme_width(char, ambiguous_width: ambiguous_width)
          break if used_cells + width > max_cells

          result << char
          used_cells += width
        end

        result
      end

      def drop_cells(text, cells_to_drop, ambiguous_width: 1)
        used_cells = 0
        graphemes(text).each_with_object(+'') do |char, result|
          width = grapheme_width(char, ambiguous_width: ambiguous_width)
          if used_cells < cells_to_drop
            used_cells += width
            next
          end

          result << char
        end
      end

      def split_cells(text, max_cells, ambiguous_width: 1)
        return [text.to_s] if max_cells <= 0

        chunks = []
        current = +''
        used_cells = 0

        graphemes(text).each do |char|
          width = grapheme_width(char, ambiguous_width: ambiguous_width)
          if used_cells.positive? && used_cells + width > max_cells
            chunks << current
            current = +''
            used_cells = 0
          end

          current << char
          used_cells += width
        end

        chunks << current unless current.empty?
        chunks
      end

      def char_width(char, ambiguous_width: 1)
        codepoint = char.ord
        return 0 if combining?(codepoint)
        return 0 if codepoint < 32 || codepoint == 0x7f
        return 2 if wide?(codepoint)
        return ambiguous_width if ambiguous?(codepoint)

        1
      end

      def grapheme_width(grapheme, ambiguous_width: 1)
        codepoints = grapheme.codepoints
        return 0 if codepoints.empty? || codepoints.all? { |codepoint| combining?(codepoint) }
        return 2 if grapheme.include?("\u200d") || grapheme.include?("\ufe0f") || grapheme.include?("\u20e3") ||
                    grapheme.match?(/[\u{1f1e6}-\u{1f1ff}]{2}/)

        codepoints.map do |codepoint|
          char_width(codepoint.chr(Encoding::UTF_8), ambiguous_width: ambiguous_width)
        end.max || 0
      end

      def combining?(codepoint)
        (0x0300..0x036f).cover?(codepoint) ||
          (0x1ab0..0x1aff).cover?(codepoint) ||
          (0x1dc0..0x1dff).cover?(codepoint) ||
          (0x20d0..0x20ff).cover?(codepoint) ||
          (0xfe00..0xfe0f).cover?(codepoint) ||
          (0xfe20..0xfe2f).cover?(codepoint) ||
          (0xe0100..0xe01ef).cover?(codepoint)
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

      def ambiguous?(codepoint)
        return false if codepoint < 0x00a1

        AMBIGUOUS_RANGES.any? { |range| range.cover?(codepoint) }
      end
    end
  end
end
