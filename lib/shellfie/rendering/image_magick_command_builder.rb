# frozen_string_literal: true

require 'mini_magick'

module Shellfie
  module Rendering
    class ImageMagickCommandBuilder
      class << self
        def convert(&block)
          MiniMagick.convert(&block)
        end

        def canvas(convert, width:, height:, background:)
          convert.size "#{width}x#{height}"
          convert << background
        end

        def output(convert, path, format: nil)
          convert << output_path(path, format: format || File.extname(path).delete_prefix('.'))
        end

        def output_path(path, format:)
          format == 'apng' ? "apng:#{path}" : path
        end

        def draw(convert, command)
          convert.draw command
        end

        def rectangle(convert, x1, y1, x2, y2)
          draw(convert, "rectangle #{x1},#{y1} #{x2},#{y2}")
        end

        def rectangles(convert, rectangles)
          return if rectangles.empty?

          draw(convert, rectangles.map do |rect|
            "rectangle #{rect[:x1]},#{rect[:y1]} #{rect[:x2]},#{rect[:y2]}"
          end.join(' '))
        end

        def round_rectangle(convert, x1, y1, x2, y2, radius)
          draw(convert, "roundrectangle #{x1},#{y1} #{x2},#{y2} #{radius},#{radius}")
        end

        def line(convert, x1, y1, x2, y2)
          draw(convert, "line #{x1},#{y1} #{x2},#{y2}")
        end

        def lines(convert, lines)
          return if lines.empty?

          draw(convert, lines.map { |line| "line #{line[:x1]},#{line[:y1]} #{line[:x2]},#{line[:y2]}" }.join(' '))
        end

        def circle(convert, center_x, center_y, radius)
          draw(convert, "circle #{center_x},#{center_y} #{center_x + radius},#{center_y}")
        end

        def point(convert, x, y)
          draw(convert, "point #{x},#{y}")
        end

        def region(convert, x:, y:, width:, height:)
          convert.region "#{width}x#{height}+#{x}+#{y}"
        end

        def clear_region(convert)
          convert << '+region'
        end

        def composite_over(convert)
          convert.compose 'over'
          convert.composite
        end
      end
    end
  end
end
