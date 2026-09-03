# frozen_string_literal: true

require_relative 'line_layout'

module Shellfie
  module Rendering
    class Geometry
      def initialize(config:, theme:)
        @config = config
        @theme = theme
      end

      def build(lines, scale:, shadow:)
        font_config = @theme.font
        line_height = font_config[:size] * font_config[:line_height]
        display_lines, visible_count = display_lines(lines, font_config, line_height)
        total_height = @config.window[:height] || (title_bar_height + ([visible_count,
                                                                        1].max * line_height) + (padding * 2))
        margin = canvas_margin(scale, shadow && !exact_size?)
        geometry = geometry_hash(
          display_lines,
          font_config,
          line_height,
          total_height,
          scale,
          margin,
          shadow && !exact_size?,
          visible_count
        )
        validate_pixel_limit!(geometry)
        geometry
      end

    private

      def display_lines(lines, font_config, line_height)
        layout = LineLayout.new(@config)
        display_lines = layout.prepare(
          lines,
          content_width: [width - (padding * 2), 1].max,
          font_size: font_config[:size],
          title_bar_height: title_bar_height,
          padding: padding,
          line_height: line_height
        )
        [display_lines, layout.visible_count]
      end

      def geometry_hash(lines, font_config, line_height, total_height, scale, margin, shadow, visible_count)
        {
          lines: lines,
          visible_line_count: visible_count,
          font_config: font_config,
          width: width,
          height: total_height,
          padding: padding,
          line_height: line_height,
          font_size: font_config[:size],
          title_bar_height: title_bar_height,
          logical_width: width,
          logical_height: total_height.ceil,
          scale: scale,
          scaled_width: (width * scale).to_i,
          scaled_height: (total_height * scale).ceil,
          scaled_padding: (padding * scale).to_i,
          scaled_line_height: (line_height * scale).ceil,
          scaled_font_size: (font_config[:size] * scale).to_i,
          scaled_title_bar: (title_bar_height * scale).to_i,
          scaled_radius: (corner_radius * scale).to_i,
          scroll_offset: @config.window[:scroll_offset].to_f,
          ambiguous_width: @config.window[:ambiguous_width],
          margin: margin,
          canvas_width: (width * scale).to_i + (margin * 2),
          canvas_height: (total_height * scale).ceil + (margin * 2),
          shadow: shadow
        }
      end

      def width
        @config.window[:width]
      end

      def padding
        @config.window[:padding]
      end

      def title_bar_height
        @config.headless ? 0 : @theme.window_decoration[:title_bar_height]
      end

      def corner_radius
        @config.headless ? 0 : @theme.window_decoration[:corner_radius]
      end

      def exact_size?
        @config.window[:exact_size]
      end

      def canvas_margin(scale, shadow)
        configured = @config.window[:margin]
        return (configured * scale).to_i if configured
        return 0 if @config.headless && !shadow
        return 0 if exact_size?
        return (10 * scale).to_i unless shadow

        shadow_config = @theme.window_decoration[:shadow]
        (([shadow_config[:blur].to_i, shadow_config[:offset_x].to_i.abs,
           shadow_config[:offset_y].to_i.abs].max + 10) * scale).to_i
      end

      def validate_pixel_limit!(geometry)
        pixels = geometry[:canvas_width] * geometry[:canvas_height]
        return if pixels <= @config.limits[:max_pixels]

        raise ResourceLimitError, "Estimated image is too large (#{pixels} pixels, max #{@config.limits[:max_pixels]})"
      end
    end
  end
end
