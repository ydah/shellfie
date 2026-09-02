# frozen_string_literal: true

require "tempfile"
require_relative "../rendering/image_magick_command_builder"

module Shellfie
  class GifPalette
    def initialize(config:, theme:, command_builder: ImageMagickCommandBuilder)
      @config = config
      @theme = theme
      @command_builder = command_builder
      @temporary_files = []
    end

    def apply(convert, images: [])
      convert.dither(dither_mode)

      case @config.animation[:palette]
      when "global"
        apply_global_palette(convert, images)
      when "theme"
        apply_theme_palette(convert)
      else
        convert.colors color_count
      end
    end

    def cleanup
      @temporary_files.each { |file| file.close! if file.respond_to?(:close!) }
      @temporary_files.clear
    end

    private

    def apply_global_palette(convert, images)
      palette_path = build_global_palette(images)
      convert.remap palette_path if palette_path
      convert.colors color_count
    end

    def apply_theme_palette(convert)
      palette_path = build_theme_palette
      convert.remap palette_path if palette_path
      convert.colors(theme_color_count)
    end

    def build_global_palette(images)
      return nil if images.empty?

      path = palette_path
      @command_builder.convert do |convert|
        images.each { |image| convert << image[:path] }
        convert.append
        convert.colors 256
        convert.unique_colors
        @command_builder.output(convert, path, format: "png")
      end
      path
    end

    def build_theme_palette
      colors = theme_colors.first(color_count)
      return nil if colors.empty?

      path = palette_path
      @command_builder.convert do |convert|
        @command_builder.canvas(convert, width: colors.size, height: 1, background: "xc:transparent")
        colors.each_with_index do |color, index|
          convert.fill color
          @command_builder.point(convert, index, 0)
        end
        @command_builder.output(convert, path, format: "png")
      end
      path
    end

    def palette_path
      file = Tempfile.new(["shellfie-palette", ".png"])
      @temporary_files << file
      file.close
      file.path
    end

    def dither_mode
      @config.animation[:dither] ? "FloydSteinberg" : "None"
    end

    def theme_color_count
      [[theme_colors.size, [16, color_count].min].max, color_count].min
    end

    def theme_colors
      @theme_colors ||= [
        @theme.colors.values,
        @theme.button_colors,
        @theme.window_decoration.dig(:shadow, :color),
        @theme.window_decoration[:border]
      ].flatten.compact.uniq
    end

    def color_count
      @config.animation[:gif_colors]
    end
  end
end
