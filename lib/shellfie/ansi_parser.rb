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
    :underline_style,
    :underline_color,
    :dim,
    :reverse,
    :strikethrough,
    :overline,
    :blink,
    :conceal,
    keyword_init: true
  )

  class AnsiParser
    ANSI_REGEX = /\e\[([0-9;:]*)m/

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
      @underline_style = nil
      @underline_color = nil
      @dim = false
      @reverse = false
      @strikethrough = false
      @overline = false
      @blink = false
      @conceal = false
    end

    def create_segment(text)
      Segment.new(
        text: text,
        foreground: @foreground,
        background: @background,
        bold: @bold,
        italic: @italic,
        underline: @underline,
        underline_style: @underline_style,
        underline_color: @underline_color,
        dim: @dim,
        reverse: @reverse,
        strikethrough: @strikethrough,
        overline: @overline,
        blink: @blink,
        conceal: @conceal
      )
    end

    def process_codes(codes_str)
      return reset_state if codes_str.empty?

      codes = sgr_codes(codes_str)
      i = 0

      while i < codes.length
        code = codes[i]

        if code.is_a?(Array) && code.first == :underline_style
          @underline_style = %i[none single double curly dotted dashed][code.last]
          @underline = @underline_style && @underline_style != :none
          i += 1
          next
        end

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
          @underline_style = :single
        when 5, 6
          @blink = true
        when 8
          @conceal = true
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
          @underline_style = nil
        when 25
          @blink = false
        when 27
          @reverse = false
        when 28
          @conceal = false
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
        when 21
          @underline = true
          @underline_style = :double
        when 53
          @overline = true
        when 55
          @overline = false
        when 58
          i, @underline_color = AnsiColors.parse_extended_color(codes, i)
        when 59
          @underline_color = nil
        end

        i += 1
      end
    end

    def sgr_codes(value)
      value.split(";").flat_map do |field|
        parts = field.split(":", -1)
        next(field.empty? ? 0 : field.to_i) if parts.size == 1

        code, mode = parts.values_at(0, 1).map(&:to_i)
        if code == 4 && parts.size == 2 && parts.last.match?(/\A[0-5]\z/)
          [[:underline_style, parts.last.to_i]]
        elsif [38, 48, 58].include?(code) && mode == 2 && [5, 6].include?(parts.size) && parts.last(3).all? { |item| item.match?(/\A\d+\z/) }
          [code, mode, *parts.last(3).map(&:to_i)]
        elsif [38, 48, 58].include?(code) && mode == 5 && parts.size == 3 && parts.last.match?(/\A\d+\z/)
          [code, mode, parts.last.to_i]
        else
          []
        end
      end
    end

  end
end
