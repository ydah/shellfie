# frozen_string_literal: true

module Shellfie
  module Themes
    class Configured
      def initialize(base_theme, name:, colors: {}, window_decoration: {}, font: {})
        @base_theme = base_theme
        @name = name
        @colors = colors || {}
        @window_decoration = window_decoration || {}
        @font = font || {}
      end

      def name
        @name
      end

      def window_decoration
        deep_merge(@base_theme.window_decoration, @window_decoration)
      end

      def colors
        @base_theme.colors.merge(@colors)
      end

      def font
        @base_theme.font.merge(@font)
      end

      def button_colors
        @base_theme.button_colors
      end

      def button_style
        @base_theme.button_style
      end

      def buttons_position
        @base_theme.buttons_position
      end

      def title_alignment
        @base_theme.title_alignment
      end

      def color_for(name)
        return name if name.is_a?(String) && name.start_with?("#")

        colors[name.to_sym] || colors[:foreground]
      end

      private

      def deep_merge(base, overrides)
        base.merge(overrides) do |_key, left, right|
          left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
        end
      end
    end
  end
end
