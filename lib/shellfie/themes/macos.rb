# frozen_string_literal: true

require_relative "base"

module Shellfie
  module Themes
    class MacOS < Base
      def name
        "macos"
      end

      def window_decoration
        {
          title_bar_height: 28,
          button_size: 12,
          button_spacing: 8,
          corner_radius: 10,
          shadow: { blur: 50, offset_x: 0, offset_y: 25, color: "rgba(0,0,0,0.4)" }
        }
      end

      def colors
        super.merge(
          background: "#1e1e1e",
          title_bar: "#3c3c3c",
          title_text: "#ffffff"
        )
      end

      def button_colors
        %w[#ff5f56 #ffbd2e #27c93f]
      end

      def button_style
        :circles
      end

      def buttons_position
        :left
      end

      def font
        {
          family: "SF Mono",
          size: 14,
          line_height: 1.4
        }
      end
    end
  end
end
