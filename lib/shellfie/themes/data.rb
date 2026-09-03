# frozen_string_literal: true

module Shellfie
  module Themes
    class Data
      attr_reader :name, :colors, :window_decoration, :button_colors, :buttons_position, :button_style, :font,
                  :title_alignment

      def self.from_theme(theme, name:, colors: {}, window_decoration: {}, font: {}, headless: false)
        data = new(
          name: name,
          colors: theme.colors.merge(colors || {}),
          window_decoration: deep_merge(theme.window_decoration, window_decoration || {}),
          button_colors: theme.button_colors,
          buttons_position: theme.buttons_position,
          button_style: theme.button_style,
          font: theme.font.merge(font || {}),
          title_alignment: theme.title_alignment
        )
        headless ? data.headless : data
      end

      def self.deep_merge(base, overrides)
        base.merge(overrides) do |_key, left, right|
          left.is_a?(Hash) && right.is_a?(Hash) ? deep_merge(left, right) : right
        end
      end

      def initialize(name:, colors:, window_decoration:, button_colors:, buttons_position:, button_style:, font:,
                     title_alignment:)
        @name = name
        @colors = deep_freeze_copy(colors)
        @window_decoration = deep_freeze_copy(window_decoration)
        @button_colors = deep_freeze_copy(button_colors)
        @buttons_position = buttons_position
        @button_style = button_style
        @font = deep_freeze_copy(font)
        @title_alignment = title_alignment
        freeze
      end

      def color_for(name)
        return name if name.is_a?(String) && name.start_with?('#')

        colors[name.to_sym] || colors[:foreground]
      end

      def headless
        self.class.new(
          name: name,
          colors: colors,
          window_decoration: self.class.deep_merge(
            window_decoration,
            title_bar_height: 0,
            corner_radius: 0,
            button_size: 0,
            button_spacing: 0
          ),
          button_colors: [],
          buttons_position: :left,
          button_style: :none,
          font: font,
          title_alignment: :left
        )
      end

    private

      def deep_freeze_copy(value)
        copy = case value
               when Hash
                 value.each_with_object({}) { |(key, nested), result| result[key] = deep_freeze_copy(nested) }
               when Array
                 value.map { |nested| deep_freeze_copy(nested) }
               else
                 value
               end
        copy.freeze
      end
    end
  end
end
