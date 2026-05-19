# frozen_string_literal: true

module Shellfie
  class GifPalette
    def initialize(config:, theme:)
      @config = config
      @theme = theme
    end

    def apply(convert)
      convert.dither(@config.animation[:dither] ? "FloydSteinberg" : "None")
      convert.colors(color_count)
    end

    private

    def color_count
      case @config.animation[:palette]
      when "theme"
        [[theme_color_count, 16].max, 256].min
      else
        256
      end
    end

    def theme_color_count
      @theme.colors.values.compact.uniq.size
    end
  end
end
