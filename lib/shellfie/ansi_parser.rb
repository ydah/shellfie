# frozen_string_literal: true

require "strscan"
require_relative "ansi_colors"
require_relative "ansi_normalizer"

module Shellfie
  Segment = Struct.new(
    :text,
    :foreground,
    :background,
    :bold,
    :italic,
    :underline,
    :dim,
    :reverse,
    :strikethrough,
    :overline,
    keyword_init: true
  )

  class AnsiParser
    ANSI_REGEX = /\e\[([0-9;]*)m/

    def initialize(state_mode: :persistent, tab_width: 8)
      @state_mode = state_mode.to_sym
      @tab_width = tab_width
      reset_state
    end

    def parse(text)
      reset_state if @state_mode == :line

      segments = []
      scanner = StringScanner.new(AnsiNormalizer.normalize(text.to_s, tab_width: @tab_width))
      current_text = +""

      until scanner.eos?
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
      @dim = false
      @reverse = false
      @strikethrough = false
      @overline = false
    end

    def create_segment(text)
      Segment.new(
        text: text,
        foreground: @foreground,
        background: @background,
        bold: @bold,
        italic: @italic,
        underline: @underline,
        dim: @dim,
        reverse: @reverse,
        strikethrough: @strikethrough,
        overline: @overline
      )
    end

    def process_codes(codes_str)
      return reset_state if codes_str.empty?

      codes = codes_str.split(";").map { |code| code.empty? ? 0 : code.to_i }
      i = 0

      while i < codes.length
        code = codes[i]

        case code
        when 0
          reset_state
        when 1
          @bold = true
        when 2
          @dim = true
        when 3
          @italic = true
        when 4
          @underline = true
        when 7
          @reverse = true
        when 9
          @strikethrough = true
        when 22
          @bold = false
          @dim = false
        when 23
          @italic = false
        when 24
          @underline = false
        when 27
          @reverse = false
        when 29
          @strikethrough = false
        when 30..37, 90..97
          @foreground = AnsiColors::COLORS[code]
        when 38
          i, @foreground = AnsiColors.parse_extended_color(codes, i)
        when 39
          @foreground = nil
        when 40..47, 100..107
          @background = AnsiColors::BG_COLORS[code]
        when 48
          i, @background = AnsiColors.parse_extended_color(codes, i)
        when 49
          @background = nil
        when 53
          @overline = true
        when 55
          @overline = false
        end

        i += 1
      end
    end

  end
end
