# frozen_string_literal: true

require_relative "../text_metrics"

module Shellfie
  module Rendering
    module TextPainter
      def draw_content(convert, geometry)
        content_y = geometry[:margin] + geometry[:scaled_title_bar] + geometry[:scaled_padding]
        geometry[:lines].each_with_index do |line, index|
          top = content_y + index * geometry[:scaled_line_height]
          baseline = top + geometry[:scaled_font_size]
          x = geometry[:margin] + geometry[:scaled_padding]

          if line[:selected]
            convert.fill theme.colors[:selection]
            convert.draw "rectangle #{x},#{top} #{x + geometry[:scaled_width] - geometry[:scaled_padding] * 2}," \
                         "#{top + geometry[:scaled_line_height]}"
          end

          draw_line_segments(convert, line[:segments], x, baseline, geometry)
        end
      end

      def draw_line_segments(convert, segments, x, baseline, geometry)
        current_x = x

        segments.each do |segment|
          next if segment.text.to_s.empty?

          text = segment.text.to_s
          width = TextMetrics.pixel_width(text, geometry[:scaled_font_size])
          top = baseline - geometry[:scaled_font_size]
          bottom = top + geometry[:scaled_line_height]
          foreground, background = segment_colors(segment)

          if background
            convert.fill background
            convert.draw "rectangle #{current_x},#{top} #{current_x + width},#{bottom}"
          end

          draw_text(
            convert,
            text,
            current_x,
            top,
            foreground,
            geometry[:scaled_font_size],
            geometry[:font_config],
            bold: segment.bold,
            italic: segment.italic
          )
          draw_text_decoration(convert, segment, current_x, width, baseline, geometry)
          current_x += width
        end
      end

      def segment_colors(segment)
        foreground = segment.foreground ? theme.color_for(segment.foreground) : theme.colors[:foreground]
        background = segment.background ? theme.color_for(segment.background) : nil

        if segment.reverse
          foreground, background = background || theme.colors[:background], foreground
        end

        foreground = color_with_opacity(foreground, 0.6, true) if segment.dim
        [foreground, background]
      end

      def draw_text(convert, text, x, y, color, font_size, font_config, bold: false, italic: false)
        convert.gravity "NorthWest"
        convert.fill color
        convert.stroke "none"
        font = font_resolver.resolve(font_config, italic: italic)
        convert.font font if font
        convert.pointsize font_size
        convert.weight(bold ? 700 : 400)
        convert.style(italic ? "Italic" : "Normal")
        convert.draw "text #{x},#{y} '#{escape_text(text)}'"
      end

      def draw_text_decoration(convert, segment, x, width, baseline, geometry)
        return unless segment.underline || segment.strikethrough || segment.overline

        line_width = [(geometry[:scaled_font_size] / 12.0).ceil, 1].max
        convert.stroke segment_colors(segment).first
        convert.strokewidth line_width

        if segment.underline
          y = baseline + (geometry[:scaled_font_size] * 0.12).ceil
          convert.draw "line #{x},#{y} #{x + width},#{y}"
        end
        if segment.strikethrough
          y = baseline - (geometry[:scaled_font_size] * 0.35).ceil
          convert.draw "line #{x},#{y} #{x + width},#{y}"
        end
        if segment.overline
          y = baseline - geometry[:scaled_font_size]
          convert.draw "line #{x},#{y} #{x + width},#{y}"
        end

        convert.stroke "none"
      end

      def fit_text(text, max_width, font_size)
        return "" if max_width <= 0
        return text if TextMetrics.pixel_width(text, font_size) <= max_width

        max_cells = [(max_width / (font_size * 0.6)).floor - 3, 0].max
        "#{TextMetrics.take_cells(text, max_cells)}..."
      end

      def color_with_opacity(color, opacity, allow_rgba)
        return color unless allow_rgba && opacity < 1.0

        if color.to_s.match?(/\A#[0-9a-fA-F]{6}\z/)
          r = color[1, 2].to_i(16)
          g = color[3, 2].to_i(16)
          b = color[5, 2].to_i(16)
          "rgba(#{r},#{g},#{b},#{opacity})"
        else
          color
        end
      end

      def escape_text(text)
        text.to_s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")
      end
    end
  end
end
