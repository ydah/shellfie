# frozen_string_literal: true

require_relative 'shape_helpers'
require_relative 'image_magick_command_builder'
require_relative '../terminal/text_metrics'

module Shellfie
  module Rendering
    module WindowChrome
      include ShapeHelpers

      def draw_shadow(convert, geometry)
        shadow = theme.window_decoration[:shadow]
        scale = geometry[:scale]
        offset_x = (shadow[:offset_x] * scale).to_i
        offset_y = (shadow[:offset_y] * scale).to_i
        radius = geometry[:scaled_radius]
        margin = geometry[:margin]

        convert.fill shadow[:color]
        draw_roundrect(
          convert,
          margin + offset_x,
          margin + offset_y,
          margin + geometry[:scaled_width] - 1 + offset_x,
          margin + geometry[:scaled_height] - 1 + offset_y,
          radius
        )
        convert.blur "0x#{(shadow[:blur] * scale).to_i}"
      end

      def draw_window(convert, geometry, transparent:)
        margin = geometry[:margin]
        background = color_with_opacity(theme.colors[:background], config.window[:opacity], true)

        convert.fill background
        draw_roundrect(
          convert,
          margin,
          margin,
          margin + geometry[:scaled_width] - 1,
          margin + geometry[:scaled_height] - 1,
          geometry[:scaled_radius]
        )

        draw_border(convert, geometry)
      end

      def draw_title_bar(convert, geometry)
        margin = geometry[:margin]
        title_y2 = margin + geometry[:scaled_title_bar] - 1

        convert.fill theme.colors[:title_bar]
        draw_roundrect(
          convert,
          margin,
          margin,
          margin + geometry[:scaled_width] - 1,
          title_y2,
          geometry[:scaled_radius]
        )
        convert.fill theme.colors[:title_bar]
        ImageMagickCommandBuilder.rectangle(
          convert,
          margin,
          margin + geometry[:scaled_radius],
          margin + geometry[:scaled_width] - 1,
          title_y2
        )

        draw_title_separator(convert, geometry, title_y2)
        draw_buttons(convert, geometry)
        draw_title(convert, geometry)
      end

      def draw_title_separator(convert, geometry, y)
        color = theme.colors[:title_bar_border]
        return unless color

        convert.stroke color
        convert.strokewidth 1
        ImageMagickCommandBuilder.line(convert, geometry[:margin], y, geometry[:margin] + geometry[:scaled_width] - 1,
                                       y)
        convert.stroke 'none'
      end

      def draw_border(convert, geometry)
        color = theme.colors[:border]
        return unless color

        convert.fill 'none'
        convert.stroke color
        convert.strokewidth [geometry[:scale].to_i, 1].max
        draw_roundrect(
          convert,
          geometry[:margin],
          geometry[:margin],
          geometry[:margin] + geometry[:scaled_width] - 1,
          geometry[:margin] + geometry[:scaled_height] - 1,
          geometry[:scaled_radius]
        )
        convert.stroke 'none'
      end

      def draw_buttons(convert, geometry)
        return draw_windows_buttons(convert, geometry) if theme.button_style == :icons

        button_radius = ((theme.window_decoration[:button_size] / 2.0) * geometry[:scale]).to_i
        centers = circle_button_centers(geometry)

        centers.each_with_index do |(x, y), index|
          convert.fill theme.button_colors[index]
          convert.stroke 'rgba(0,0,0,0.18)'
          convert.strokewidth [geometry[:scale].to_i, 1].max
          ImageMagickCommandBuilder.circle(convert, x, y, button_radius)
        end
        convert.stroke 'none'
      end

      def circle_button_centers(geometry)
        scale = geometry[:scale]
        size = (theme.window_decoration[:button_size] * scale).to_i
        spacing = ((theme.window_decoration[:button_spacing] + theme.window_decoration[:button_size]) * scale).to_i
        y = geometry[:margin] + (geometry[:scaled_title_bar] / 2)

        start_x = if theme.buttons_position == :left
                    geometry[:margin] + (16 * scale).to_i
                  else
                    group_width = (size * 3) + ((theme.window_decoration[:button_spacing] * scale).to_i * 2)
                    geometry[:margin] + geometry[:scaled_width] - (16 * scale).to_i - group_width + (size / 2)
                  end

        Array.new(3) { |index| [start_x + (index * spacing), y] }
      end

      def draw_windows_buttons(convert, geometry)
        scale = geometry[:scale]
        button_width = ((theme.window_decoration[:button_width] || 46) * scale).to_i
        icon_size = (10 * scale).to_i
        start_x = geometry[:margin] + geometry[:scaled_width] - (button_width * 3)
        center_y = geometry[:margin] + (geometry[:scaled_title_bar] / 2)
        color = theme.colors[:title_text]

        convert.stroke color
        convert.strokewidth [scale.to_i, 1].max
        convert.fill 'none'

        3.times do |index|
          center_x = start_x + (button_width * index) + (button_width / 2)
          draw_windows_icon(convert, index, center_x, center_y, icon_size)
        end

        convert.stroke 'none'
      end

      def draw_title(convert, geometry)
        scaled_font_size = geometry[:scaled_font_size]
        group_width = button_group_width(geometry)
        reserve_left = theme.buttons_position == :left ? group_width + (32 * geometry[:scale]).to_i : (12 * geometry[:scale]).to_i
        reserve_right = theme.buttons_position == :right ? group_width + (12 * geometry[:scale]).to_i : (12 * geometry[:scale]).to_i
        available_width = geometry[:scaled_width] - reserve_left - reserve_right
        title = fit_text(config.title.to_s, available_width, scaled_font_size)
        title_width = TextMetrics.pixel_width(title, scaled_font_size, ambiguous_width: config.window[:ambiguous_width])
        min_x = geometry[:margin] + reserve_left
        max_x = geometry[:margin] + geometry[:scaled_width] - reserve_right - title_width
        centered_x = geometry[:margin] + ((geometry[:scaled_width] - title_width) / 2)
        x = title_x(min_x, max_x, centered_x)
        y = geometry[:margin] + (geometry[:scaled_title_bar] / 2) + (scaled_font_size * 0.6).round

        draw_text(convert, title, x, y - scaled_font_size, theme.colors[:title_text], scaled_font_size,
                  geometry[:font_config])
      end

      def title_x(min_x, max_x, centered_x)
        case theme.title_alignment
        when :left
          min_x
        when :right
          max_x
        else
          [[centered_x, min_x].max, max_x].min
        end
      end

      def button_group_width(geometry)
        scale = geometry[:scale]
        if theme.button_style == :icons
          ((theme.window_decoration[:button_width] || 46) * 3 * scale).to_i
        else
          size = theme.window_decoration[:button_size]
          spacing = theme.window_decoration[:button_spacing]
          (((size * 3) + (spacing * 2)) * scale).to_i
        end
      end
    end
  end
end
