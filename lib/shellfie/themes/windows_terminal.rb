# frozen_string_literal: true

require_relative "base"

module Shellfie
  module Themes
    class WindowsTerminal < Base
      def name
        "windows"
      end

      def window_decoration
        {
          title_bar_height: 32,
          button_size: 10,
          button_spacing: 0,
          corner_radius: 0,
          shadow: { blur: 15, offset_x: 0, offset_y: 5, color: "rgba(0,0,0,0.25)" }
        }
      end

      def colors
        super.merge(
          background: "#0c0c0c",
          foreground: "#cccccc",
          title_bar: "#1f1f1f",
          title_text: "#ffffff",
          black: "#0c0c0c",
          red: "#c50f1f",
          green: "#13a10e",
          yellow: "#c19c00",
          blue: "#0037da",
          magenta: "#881798",
          cyan: "#3a96dd",
          white: "#cccccc",
          bright_black: "#767676",
          bright_red: "#e74856",
          bright_green: "#16c60c",
          bright_yellow: "#f9f1a5",
          bright_blue: "#3b78ff",
          bright_magenta: "#b4009e",
          bright_cyan: "#61d6d6",
          bright_white: "#f2f2f2"
        )
      end

      def button_style
        :icons
      end

      def buttons_position
        :right
      end

      def font
        {
          family: "Cascadia Mono",
          size: 14,
          line_height: 1.3
        }
      end
    end
  end
end
