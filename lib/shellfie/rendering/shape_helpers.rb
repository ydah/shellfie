# frozen_string_literal: true

module Shellfie
  module Rendering
    module ShapeHelpers
      def draw_roundrect(convert, x1, y1, x2, y2, radius)
        if radius.positive?
          convert.draw "roundrectangle #{x1},#{y1} #{x2},#{y2} #{radius},#{radius}"
        else
          convert.draw "rectangle #{x1},#{y1} #{x2},#{y2}"
        end
      end

      def draw_windows_icon(convert, index, center_x, center_y, icon_size)
        case index
        when 0
          convert.draw "line #{center_x - icon_size / 2},#{center_y} #{center_x + icon_size / 2},#{center_y}"
        when 1
          convert.draw "rectangle #{center_x - icon_size / 2},#{center_y - icon_size / 2} " \
                       "#{center_x + icon_size / 2},#{center_y + icon_size / 2}"
        when 2
          convert.draw "line #{center_x - icon_size / 2},#{center_y - icon_size / 2} " \
                       "#{center_x + icon_size / 2},#{center_y + icon_size / 2}"
          convert.draw "line #{center_x + icon_size / 2},#{center_y - icon_size / 2} " \
                       "#{center_x - icon_size / 2},#{center_y + icon_size / 2}"
        end
      end
    end
  end
end
