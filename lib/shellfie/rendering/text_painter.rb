# frozen_string_literal: true

require_relative 'image_magick_command_builder'
require_relative '../terminal/text_metrics'

module Shellfie
  module Rendering
    module TextPainter
      def draw_content(convert, geometry)
        content_y = content_origin_y(geometry)
        draw_selected_backgrounds(convert, geometry, content_y)

        geometry[:lines].each_with_index do |line, index|
          top = content_y + (index * geometry[:scaled_line_height])
          baseline = top + geometry[:scaled_font_size]
          x = geometry[:margin] + geometry[:scaled_padding]

          draw_line_segments(convert, line[:segments], x, baseline, geometry)
        end
      end

      def draw_line_segments(convert, segments, x, baseline, geometry)
        positioned_segments = position_segments(segments, x, baseline, geometry)
        draw_segment_backgrounds(convert, positioned_segments)
        draw_positioned_segments(convert, positioned_segments, geometry)
      end

      def position_segments(segments, x, baseline, geometry)
        current_x = x
        segments.each_with_object([]) do |segment, result|
          text = segment.text.to_s
          next if text.empty?

          width = TextMetrics.pixel_width(text, geometry[:scaled_font_size],
                                          ambiguous_width: geometry[:ambiguous_width])
          top = baseline - geometry[:scaled_font_size]
          foreground, background = segment_colors(segment)
          result << {
            segment: segment,
            text: text,
            x: current_x,
            width: width,
            top: top,
            bottom: top + geometry[:scaled_line_height],
            foreground: foreground,
            background: background
          }
          current_x += width
        end
      end

      def draw_segment_backgrounds(convert, positioned_segments)
        positioned_segments
          .select { |item| item[:background] }
          .group_by { |item| item[:background] }
          .each do |background, items|
            convert.fill background
            ImageMagickCommandBuilder.rectangles(
              convert,
              items.map { |item| { x1: item[:x], y1: item[:top], x2: item[:x] + item[:width], y2: item[:bottom] } }
            )
          end
      end

      def draw_positioned_segments(convert, positioned_segments, geometry)
        positioned_segments.each do |item|
          unless item[:segment].conceal
            draw_text(
              convert,
              item[:text],
              item[:x],
              item[:top],
              item[:foreground],
              geometry[:scaled_font_size],
              geometry[:font_config],
              bold: item[:segment].bold,
              italic: item[:segment].italic
            )
          end
          draw_text_decoration(
            convert,
            item[:segment],
            item[:x],
            item[:width],
            item[:top] + geometry[:scaled_font_size],
            geometry
          )
        end
      end

      def segment_colors(segment)
        foreground = segment.foreground ? theme.color_for(segment.foreground) : theme.colors[:foreground]
        background = segment.background ? theme.color_for(segment.background) : nil

        foreground, background = background || theme.colors[:background], foreground if segment.reverse

        foreground = color_with_opacity(foreground, 0.6, true) if segment.dim
        [foreground, background]
      end

      def draw_text(convert, text, x, y, color, font_size, font_config, bold: false, italic: false)
        convert.gravity 'NorthWest'
        convert.fill color
        convert.stroke 'none'
        font = font_resolver.resolve(font_config, italic: italic)
        convert.font font if font
        convert.pointsize font_size
        convert.weight(bold ? 700 : 400)
        convert.style(italic ? 'Italic' : 'Normal')
        convert.annotate "+#{x}+#{y}", escape_text(text)
      end

      def draw_text_decoration(convert, segment, x, width, baseline, geometry)
        return if segment.conceal
        return unless segment.underline || segment.strikethrough || segment.overline

        line_width = [(geometry[:scaled_font_size] / 12.0).ceil, 1].max
        decoration_color = segment.underline_color ? theme.color_for(segment.underline_color) : segment_colors(segment).first
        convert.stroke decoration_color
        convert.strokewidth line_width
        convert.stroke_dasharray "#{line_width},#{line_width * 2}" if segment.underline_style == :dotted
        convert.stroke_dasharray "#{line_width * 3},#{line_width * 2}" if segment.underline_style == :dashed

        if segment.underline
          y = baseline + (geometry[:scaled_font_size] * 0.12).ceil
          ImageMagickCommandBuilder.line(convert, x, y, x + width, y)
          if segment.underline_style == :double
            ImageMagickCommandBuilder.line(convert, x, y + (line_width * 2), x + width,
                                           y + (line_width * 2))
          end
        end
        if segment.strikethrough
          y = baseline - (geometry[:scaled_font_size] * 0.35).ceil
          ImageMagickCommandBuilder.line(convert, x, y, x + width, y)
        end
        if segment.overline
          y = baseline - geometry[:scaled_font_size]
          ImageMagickCommandBuilder.line(convert, x, y, x + width, y)
        end

        convert.stroke 'none'
        convert.stroke_dasharray 'none' if %i[dotted dashed].include?(segment.underline_style)
      end

      def draw_selected_backgrounds(convert, geometry, content_y)
        rectangles = geometry[:lines].each_with_index.with_object([]) do |(line, index), result|
          next unless line[:selected]

          x = geometry[:margin] + geometry[:scaled_padding]
          top = content_y + (index * geometry[:scaled_line_height])
          result << {
            x1: x,
            y1: top,
            x2: x + geometry[:scaled_width] - (geometry[:scaled_padding] * 2),
            y2: top + geometry[:scaled_line_height]
          }
        end
        return if rectangles.empty?

        convert.fill theme.colors[:selection]
        ImageMagickCommandBuilder.rectangles(convert, rectangles)
      end

      def content_origin_y(geometry)
        base_y = geometry[:margin] + geometry[:scaled_title_bar] + geometry[:scaled_padding]
        base_y - (geometry[:scroll_offset].to_f * geometry[:scaled_line_height]).round
      end

      def fit_text(text, max_width, font_size)
        return '' if max_width <= 0
        return text if TextMetrics.pixel_width(text, font_size,
                                               ambiguous_width: config.window[:ambiguous_width]) <= max_width

        max_cells = [(max_width / (font_size * 0.6)).floor - 3, 0].max
        "#{TextMetrics.take_cells(text, max_cells, ambiguous_width: config.window[:ambiguous_width])}..."
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
        text.to_s
            .encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
            .gsub(/[\u0000-\u001f\u007f]/, ' ')
      end
    end
  end
end
