# frozen_string_literal: true

require_relative "base"

module Shellfie
  module Themes
    class Ubuntu < Base
      def name
        "ubuntu"
      end

      def window_decoration
        {
          title_bar_height: 36,
          button_size: 14,
          button_spacing: 6,
          corner_radius: 12,
          shadow: { blur: 30, offset_x: 0, offset_y: 15, color: "rgba(0,0,0,0.35)" }
        }
      end

      def colors
        super.merge(
          background: "#300a24",
          foreground: "#ffffff",
          title_bar: "#2c2c2c",
          title_text: "#ffffff",
          green: "#4e9a06",
          yellow: "#c4a000",
          blue: "#3465a4",
          magenta: "#75507b",
          cyan: "#06989a"
        )
      end

      def button_colors
        %w[#f46067 #f5bf55 #5fc454]
      end

      def button_style
        :circles
      end

      def buttons_position
        :right
      end

      def font
        {
          family: "Ubuntu Mono",
          size: 14,
          line_height: 1.4
        }
      end
    end
  end
end
