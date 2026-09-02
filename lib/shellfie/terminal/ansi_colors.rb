# frozen_string_literal: true

module Shellfie
  module AnsiColors
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

    XTERM_COLOR_STEPS = [0, 95, 135, 175, 215, 255].freeze

    module_function

    def parse_extended_color(codes, index)
      return [index, nil] if codes[index + 1].nil?

      case codes[index + 1]
      when 5
        color_index = codes[index + 2]
        return [index, nil] unless color_index

        [index + 2, color_256(color_index)]
      when 2
        rgb = codes.values_at(index + 2, index + 3, index + 4)
        return [index, nil] unless rgb.all? { |value| value.is_a?(Integer) && value.between?(0, 255) }

        [index + 4, format('#%02x%02x%02x', *rgb)]
      else
        [index, nil]
      end
    end

    def color_256(index)
      return nil unless index.is_a?(Integer) && index.between?(0, 255)

      if index < 16
        standard_colors[index]
      elsif index < 232
        color_cube(index - 16)
      else
        gray = ((index - 232) * 10) + 8
        format('#%02x%02x%02x', gray, gray, gray)
      end
    end

    def standard_colors
      %i[
        black red green yellow blue magenta cyan white
        bright_black bright_red bright_green bright_yellow
        bright_blue bright_magenta bright_cyan bright_white
      ]
    end

    def color_cube(index)
      r = XTERM_COLOR_STEPS[index / 36]
      g = XTERM_COLOR_STEPS[(index % 36) / 6]
      b = XTERM_COLOR_STEPS[index % 6]
      format('#%02x%02x%02x', r, g, b)
    end
  end
end
