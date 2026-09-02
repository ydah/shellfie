# frozen_string_literal: true

require_relative "image_magick_command_builder"

module Shellfie
  module Rendering
    module ShapeHelpers
      def draw_roundrect(convert, x1, y1, x2, y2, radius)
        if radius.positive?
          ImageMagickCommandBuilder.round_rectangle(convert, x1, y1, x2, y2, radius)
        else
          ImageMagickCommandBuilder.rectangle(convert, x1, y1, x2, y2)
        end
      end

      def draw_windows_icon(convert, index, center_x, center_y, icon_size)
        case index
        when 0
          ImageMagickCommandBuilder.line(convert, center_x - icon_size / 2, center_y, center_x + icon_size / 2, center_y)
        when 1
          ImageMagickCommandBuilder.rectangle(
            convert,
            center_x - icon_size / 2,
            center_y - icon_size / 2,
            center_x + icon_size / 2,
            center_y + icon_size / 2
          )
        when 2
          ImageMagickCommandBuilder.lines(
            convert,
            [
              { x1: center_x - icon_size / 2, y1: center_y - icon_size / 2,
                x2: center_x + icon_size / 2, y2: center_y + icon_size / 2 },
              { x1: center_x + icon_size / 2, y1: center_y - icon_size / 2,
                x2: center_x - icon_size / 2, y2: center_y + icon_size / 2 }
            ]
          )
        end
      end
    end
  end
end
