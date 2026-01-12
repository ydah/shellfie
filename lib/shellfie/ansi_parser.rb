# frozen_string_literal: true

require "strscan"

module Shellfie
  Segment = Struct.new(:text, :foreground, :background, :bold, :italic, :underline, keyword_init: true)

  class AnsiParser
    ANSI_REGEX = /\e\[([0-9;]*)m/

    COLORS = {
      30 => :black,
      31 => :red,
      32 => :green,
      33 => :yellow,
      34 => :blue,
      35 => :magenta,
      36 => :cyan,
      37 => :white,
      90 => :bright_black,
      91 => :bright_red,
      92 => :bright_green,
      93 => :bright_yellow,
      94 => :bright_blue,
      95 => :bright_magenta,
      96 => :bright_cyan,
      97 => :bright_white
    }.freeze

    BG_COLORS = {
      40 => :black,
      41 => :red,
      42 => :green,
      43 => :yellow,
      44 => :blue,
      45 => :magenta,
      46 => :cyan,
      47 => :white,
      100 => :bright_black,
      101 => :bright_red,
      102 => :bright_green,
      103 => :bright_yellow,
      104 => :bright_blue,
      105 => :bright_magenta,
      106 => :bright_cyan,
      107 => :bright_white
    }.freeze

    def initialize
      reset_state
    end

    def parse(text)
      segments = []
      scanner = StringScanner.new(text)
      current_text = +""

      while !scanner.eos?
        if scanner.scan(ANSI_REGEX)
          unless current_text.empty?
            segments << create_segment(current_text)
            current_text = +""
          end
          process_codes(scanner[1])
        else
          current_text << scanner.getch
        end
      end

      segments << create_segment(current_text) unless current_text.empty?
      segments
    end

    private

    def reset_state
      @foreground = nil
      @background = nil
      @bold = false
      @italic = false
      @underline = false
    end

    def create_segment(text)
      Segment.new(
        text: text,
        foreground: @foreground,
        background: @background,
        bold: @bold,
        italic: @italic,
        underline: @underline
      )
    end

    def process_codes(codes_str)
      return reset_state if codes_str.empty?

      codes = codes_str.split(";").map(&:to_i)
      i = 0

      while i < codes.length
        code = codes[i]

        case code
        when 0
          reset_state
        when 1
          @bold = true
        when 3
          @italic = true
        when 4
          @underline = true
        when 22
          @bold = false
        when 23
          @italic = false
        when 24
          @underline = false
        when 30..37, 90..97
          @foreground = COLORS[code]
        when 38
          i, @foreground = parse_extended_color(codes, i)
        when 39
          @foreground = nil
        when 40..47, 100..107
          @background = BG_COLORS[code]
        when 48
          i, @background = parse_extended_color(codes, i)
        when 49
          @background = nil
        end

        i += 1
      end
    end

    def parse_extended_color(codes, i)
      return [i, nil] if codes[i + 1].nil?

      case codes[i + 1]
      when 5
        color_index = codes[i + 2]
        [i + 2, color_256(color_index)]
      when 2
        r, g, b = codes[i + 2], codes[i + 3], codes[i + 4]
        [i + 4, format("#%02x%02x%02x", r, g, b)]
      else
        [i, nil]
      end
    end

    def color_256(index)
      return nil unless index

      if index < 16
        standard_colors = %i[
          black red green yellow blue magenta cyan white
          bright_black bright_red bright_green bright_yellow
          bright_blue bright_magenta bright_cyan bright_white
        ]
        standard_colors[index]
      elsif index < 232
        index -= 16
        r = (index / 36) * 51
        g = ((index % 36) / 6) * 51
        b = (index % 6) * 51
        format("#%02x%02x%02x", r, g, b)
      else
        gray = (index - 232) * 10 + 8
        format("#%02x%02x%02x", gray, gray, gray)
      end
    end
  end
end
