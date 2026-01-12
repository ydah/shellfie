# frozen_string_literal: true

module Shellfie
  module Themes
    class Base
      def name
        "base"
      end

      def window_decoration
        {
          title_bar_height: 28,
          button_size: 12,
          button_spacing: 8,
          corner_radius: 10,
          shadow: { blur: 20, offset_x: 0, offset_y: 10, color: "rgba(0,0,0,0.3)" }
        }
      end

      def colors
        {
          background: "#1e1e1e",
          foreground: "#ffffff",
          title_bar: "#3c3c3c",
          title_text: "#ffffff",
          black: "#000000",
          red: "#ff5555",
          green: "#50fa7b",
          yellow: "#f1fa8c",
          blue: "#6272a4",
          magenta: "#ff79c6",
          cyan: "#8be9fd",
          white: "#f8f8f2",
          bright_black: "#6272a4",
          bright_red: "#ff6e6e",
          bright_green: "#69ff94",
          bright_yellow: "#ffffa5",
          bright_blue: "#d6acff",
          bright_magenta: "#ff92df",
          bright_cyan: "#a4ffff",
          bright_white: "#ffffff"
        }
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
          family: "Monaco",
          size: 14,
          line_height: 1.4
        }
      end

      def color_for(name)
        return name if name.is_a?(String) && name.start_with?("#")

        colors[name.to_sym] || colors[:foreground]
      end
    end
  end
end
