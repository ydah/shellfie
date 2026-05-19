# frozen_string_literal: true

require_relative "themes/base"
require_relative "themes/configured"
require_relative "themes/macos"
require_relative "themes/ubuntu"
require_relative "themes/windows_terminal"

module Shellfie
  class ThemeRegistry
    WINDOW_THEMES = {
      "macos" => Themes::MacOS,
      "ubuntu" => Themes::Ubuntu,
      "windows" => Themes::WindowsTerminal
    }.freeze

    COLOR_SCHEMES = {
      "dracula" => {
        background: "#282a36",
        foreground: "#f8f8f2",
        black: "#21222c",
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
      },
      "one_dark" => {
        background: "#282c34",
        foreground: "#abb2bf",
        red: "#e06c75",
        green: "#98c379",
        yellow: "#e5c07b",
        blue: "#61afef",
        magenta: "#c678dd",
        cyan: "#56b6c2",
        white: "#abb2bf"
      },
      "solarized_dark" => {
        background: "#002b36",
        foreground: "#839496",
        red: "#dc322f",
        green: "#859900",
        yellow: "#b58900",
        blue: "#268bd2",
        magenta: "#d33682",
        cyan: "#2aa198",
        white: "#eee8d5"
      },
      "catppuccin_mocha" => {
        background: "#1e1e2e",
        foreground: "#cdd6f4",
        red: "#f38ba8",
        green: "#a6e3a1",
        yellow: "#f9e2af",
        blue: "#89b4fa",
        magenta: "#cba6f7",
        cyan: "#94e2d5",
        white: "#bac2de"
      }
    }.freeze

    class << self
      def build(config)
        base_name = config.theme == "custom" ? (config.window_theme || "macos") : (config.window_theme || config.theme)
        base_theme = fetch_window_theme(base_name).new
        colors = color_scheme(config.color_scheme).merge(config.colors)

        Themes::Configured.new(
          base_theme,
          name: config.theme,
          colors: colors,
          window_decoration: config.window_decoration,
          font: font_overrides(config)
        )
      end

      def valid_theme?(name)
        name == "custom" || WINDOW_THEMES.key?(name)
      end

      def valid_window_theme?(name)
        WINDOW_THEMES.key?(name)
      end

      def valid_color_scheme?(name)
        name.nil? || COLOR_SCHEMES.key?(name)
      end

      def available_themes
        (WINDOW_THEMES.keys + ["custom"]).sort
      end

      def available_color_schemes
        COLOR_SCHEMES.keys.sort
      end

      private

      def fetch_window_theme(name)
        WINDOW_THEMES.fetch(name) do
          raise ValidationError, "Invalid theme '#{name}'\n  → Available themes: #{available_themes.join(", ")}"
        end
      end

      def color_scheme(name)
        return {} unless name

        COLOR_SCHEMES.fetch(name)
      end

      def font_overrides(config)
        config.font == Config::DEFAULTS[:font] ? {} : config.font
      end
    end
  end
end
