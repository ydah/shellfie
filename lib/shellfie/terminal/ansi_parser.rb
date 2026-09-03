# frozen_string_literal: true

require 'strscan'
require 'uri'
require_relative 'ansi_colors'
require_relative 'ansi_normalization'
require_relative 'segment'
require_relative '../errors'

module Shellfie
  module Terminal
    class ANSIParser
      ANSI_REGEX = /\e\[([0-9;:]*)m/

      OSC_REGEX = /\e\](.*?)?(?:\a|\e\\)/m
      MAX_LINK_BYTES = 2_048
      MAX_OSC_BYTES = MAX_LINK_BYTES + 64
      LINK_SCHEMES = %w[http https mailto].freeze

      def initialize(state_mode: :persistent, tab_width: 8, osc_policy: 'ignore', graphics_policy: 'ignore')
        @state_mode = state_mode.to_sym
        @tab_width = tab_width
        @osc_policy = osc_policy.to_s
        @graphics_policy = graphics_policy.to_s
        @link = nil
        @pending_osc = +''
        reset_state
      end

      def parse(text)
        reset_line_state
        input = normalized_input(text)
        scan_segments(input)
      end

      private

      def reset_line_state
        return unless @state_mode == :line

        reset_state
        @link = nil
      end

      def normalized_input(text)
        input = @pending_osc + text.to_s
        reject_terminal_graphics!(input)
        input, @pending_osc = split_incomplete_osc(input)
        ANSINormalization.normalize(input, tab_width: @tab_width, osc_policy: @osc_policy)
      end

      def scan_segments(input)
        segments = []
        scanner = StringScanner.new(input)
        current_text = +''

        until scanner.eos?
          if scanner.scan(OSC_REGEX)
            unless current_text.empty?
              segments << create_segment(current_text)
              current_text = +''
            end
            process_osc(scanner[1])
          elsif scanner.scan(ANSI_REGEX)
            unless current_text.empty?
              segments << create_segment(current_text)
              current_text = +''
            end
            process_codes(scanner[1])
          else
            current_text << scanner.getch
          end
        end

        segments << create_segment(current_text) unless current_text.empty?
        segments
      end

      def reject_terminal_graphics!(text)
        return unless @graphics_policy == 'error' && text.match?(ANSINormalization::GRAPHICS_CONTROL_PREFIX)

        raise ValidationError, 'Terminal graphics are not supported; use window.graphics_policy: ignore to discard them'
      end

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
          conceal: @conceal,
          link: @link
        )
      end

      def process_codes(codes_str)
        return reset_state if codes_str.empty?

        codes = sgr_codes(codes_str)
        i = 0

        while i < codes.length
          code = codes[i]
          if code.is_a?(Array) && code.first == :underline_style
            apply_underline_style(code.last)
          else
            i = apply_sgr_code(code, codes, i)
          end
          i += 1
        end
      end

      def apply_underline_style(index)
        @underline_style = %i[none single double curly dotted dashed][index]
        @underline = @underline_style && @underline_style != :none
      end

      def apply_sgr_code(code, codes, index)
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
          @foreground = ANSIColors::COLORS[code]
        when 38
          index, @foreground = ANSIColors.parse_extended_color(codes, index)
        when 39
          @foreground = nil
        when 40..47, 100..107
          @background = ANSIColors::BG_COLORS[code]
        when 48
          index, @background = ANSIColors.parse_extended_color(codes, index)
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
          index, @underline_color = ANSIColors.parse_extended_color(codes, index)
        when 59
          @underline_color = nil
        end
        index
      end

      def sgr_codes(value)
        value.split(';').flat_map do |field|
          parts = field.split(':', -1)
          next(field.empty? ? 0 : field.to_i) if parts.size == 1

          code, mode = parts.values_at(0, 1).map(&:to_i)
          if code == 4 && parts.size == 2 && parts.last.match?(/\A[0-5]\z/)
            [[:underline_style, parts.last.to_i]]
          elsif [38, 48, 58].include?(code) && mode == 2 && [5, 6].include?(parts.size) && parts.last(3).all? do |item|
            item.match?(/\A\d+\z/)
          end
            [code, mode, *parts.last(3).map(&:to_i)]
          elsif [38, 48, 58].include?(code) && mode == 5 && parts.size == 3 && parts.last.match?(/\A\d+\z/)
            [code, mode, parts.last.to_i]
          else
            []
          end
        end
      end

      def process_osc(value)
        return unless value.to_s.start_with?('8;')

        uri = value.to_s.split(';', 3)[2].to_s
        @link = uri.empty? ? nil : safe_link(uri)
      end

      def safe_link(value)
        return if value.bytesize > MAX_LINK_BYTES || value.match?(/[\x00-\x1f\x7f]/)

        uri = URI.parse(value)
        value if LINK_SCHEMES.include?(uri.scheme&.downcase)
      rescue URI::InvalidURIError
        nil
      end

      def split_incomplete_osc(value)
        start = value.rindex("\e]")
        return [value, +''] unless start

        tail = value[start..]
        return [value, +''] if tail.match?(OSC_REGEX)
        return [value[0...start], tail] if tail.bytesize <= MAX_OSC_BYTES

        [value[0...start], +'']
      end
    end
  end
end
