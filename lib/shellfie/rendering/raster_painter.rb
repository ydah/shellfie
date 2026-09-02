# frozen_string_literal: true

require "tempfile"
require_relative "image_magick_command_builder"
require_relative "text_painter"
require_relative "window_chrome"

module Shellfie
  class RasterPainter
    include Rendering::TextPainter
    include Rendering::WindowChrome

    attr_reader :config, :theme, :font_resolver

    def initialize(config:, theme:, font_resolver:, chrome_cache: nil)
      @config = config
      @theme = theme
      @font_resolver = font_resolver
      @chrome_cache = chrome_cache
    end

    def paint(geometry, output_path, transparent:)
      return create_cached_image(geometry, output_path, transparent: transparent) if @chrome_cache

      create_full_image(geometry, output_path, transparent: transparent)
    end

    private

    def create_full_image(geometry, output_path, transparent:)
      return create_direct_image(geometry, output_path, transparent: transparent) unless clip_content?(geometry)

      with_temp_png do |base_path|
        with_temp_png do |content_path|
          create_chrome_image(geometry, base_path, transparent: transparent)
          create_content_layer(geometry, content_path)
          composite_layers(base_path, content_path, output_path)
        end
      end
    end

    def create_direct_image(geometry, output_path, transparent:)
      ImageMagickCommandBuilder.convert do |convert|
        ImageMagickCommandBuilder.canvas(
          convert,
          width: geometry[:canvas_width],
          height: geometry[:canvas_height],
          background: canvas_background(transparent)
        )
        draw_chrome(convert, geometry, transparent: transparent)
        draw_content(convert, geometry)
        finish_image(convert, output_path)
      end
    end

    def create_cached_image(geometry, output_path, transparent:)
      base_path = @chrome_cache.fetch(geometry, transparent: transparent) do |path|
        create_chrome_image(geometry, path, transparent: transparent)
      end
      return create_cached_direct_image(base_path, geometry, output_path) unless clip_content?(geometry)

      with_temp_png do |content_path|
        create_content_layer(geometry, content_path)
        composite_layers(base_path, content_path, output_path)
      end
    end

    def create_cached_direct_image(base_path, geometry, output_path)
      ImageMagickCommandBuilder.convert do |convert|
        convert << base_path
        draw_content(convert, geometry)
        finish_image(convert, output_path)
      end
    end

    def create_chrome_image(geometry, output_path, transparent:)
      ImageMagickCommandBuilder.convert do |convert|
        ImageMagickCommandBuilder.canvas(
          convert,
          width: geometry[:canvas_width],
          height: geometry[:canvas_height],
          background: canvas_background(transparent)
        )
        draw_chrome(convert, geometry, transparent: transparent)
        ImageMagickCommandBuilder.output(convert, output_path, format: "png")
      end
    end

    def create_content_layer(geometry, output_path)
      ImageMagickCommandBuilder.convert do |convert|
        ImageMagickCommandBuilder.canvas(
          convert,
          width: geometry[:canvas_width],
          height: geometry[:canvas_height],
          background: "xc:transparent"
        )
        ImageMagickCommandBuilder.region(convert, **content_region(geometry))
        draw_content(convert, geometry)
        ImageMagickCommandBuilder.clear_region(convert)
        ImageMagickCommandBuilder.output(convert, output_path, format: "png")
      end
    end

    def composite_layers(base_path, content_path, output_path)
      ImageMagickCommandBuilder.convert do |convert|
        convert << base_path
        convert << content_path
        ImageMagickCommandBuilder.composite_over(convert)
        finish_image(convert, output_path)
      end
    end

    def draw_chrome(convert, geometry, transparent:)
      draw_shadow(convert, geometry) if geometry[:shadow]
      draw_window(convert, geometry, transparent: transparent)
      draw_title_bar(convert, geometry) unless config.headless
    end

    def finish_image(convert, output_path)
      if config.window[:trim]
        convert.trim
        convert << "+repage"
      end
      ImageMagickCommandBuilder.output(convert, output_path)
    end

    def canvas_background(transparent)
      gradient = config.window[:background_gradient]
      return "xc:transparent" if transparent
      return "gradient:#{gradient[0]}-#{gradient[1]}" if gradient.is_a?(Array) && gradient.size == 2

      "xc:#{theme.colors[:background]}"
    end

    def clip_content?(geometry)
      geometry[:scroll_offset].to_f.positive?
    end

    def content_region(geometry)
      {
        x: geometry[:margin] + geometry[:scaled_padding],
        y: geometry[:margin] + geometry[:scaled_title_bar] + geometry[:scaled_padding],
        width: [geometry[:scaled_width] - geometry[:scaled_padding] * 2, 1].max,
        height: [geometry[:scaled_height] - geometry[:scaled_title_bar] - geometry[:scaled_padding] * 2, 1].max
      }
    end

    def with_temp_png
      file = Tempfile.new(["shellfie-layer", ".png"])
      path = file.path
      file.close
      yield path
    ensure
      File.delete(path) if path && File.exist?(path)
    end
  end
end
