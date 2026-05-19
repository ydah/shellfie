# frozen_string_literal: true

require "mini_magick"
require_relative "ansi_parser"
require_relative "dependency_checker"
require_relative "font_resolver"
require_relative "format_resolver"
require_relative "image_magick_command_builder"
require_relative "output_writer"
require_relative "render_chrome_cache"
require_relative "render_geometry"
require_relative "render_segment"
require_relative "rendering/text_painter"
require_relative "rendering/window_chrome"
require_relative "svg_raster_wrapper"
require_relative "theme_registry"

module Shellfie
  class Renderer
    include Rendering::TextPainter
    include Rendering::WindowChrome

    attr_reader :config, :theme, :font_resolver

    def initialize(config, chrome_cache: nil)
      @config = config
      @chrome_cache = chrome_cache
      @theme = ThemeRegistry.build(config)
      @ansi_parser = AnsiParser.new(state_mode: config.window[:ansi_state] || :persistent)
      @font_resolver = FontResolver.new(-> { imagemagick_command })
    end

    def render(output_path, scale: 1, shadow: true, transparent: false, format: nil)
      check_dependencies!
      lines = build_lines
      extension = FormatResolver.resolve(output_path, explicit: format, default: "png")
      OutputWriter.write(output_path, extension: extension) do |temporary_path|
        render_method = (extension == "svg") ? :create_svg_image : :create_image
        send(render_method, lines, temporary_path, scale: scale, shadow: shadow, transparent: transparent)
      end
    rescue MiniMagick::Error => e
      raise RenderError.new("ImageMagick render failed: #{e.message}", category: :render)
    end

    def estimate(scale: 1, shadow: true)
      geometry = build_geometry(build_lines, scale: scale, shadow: shadow)
      geometry.slice(:canvas_width, :canvas_height, :scaled_width, :scaled_height, :logical_width, :logical_height, :scale)
    end

    private

    def check_dependencies!
      DependencyChecker.configure_mini_magick!
      DependencyChecker.ensure_imagemagick!
    end

    def imagemagick_command
      @imagemagick_command ||= DependencyChecker.imagemagick_path.to_s
    end

    def build_lines
      config.lines.flat_map do |line|
        rendered_lines = []
        if line.prompt || line.command
          rendered_lines << {
            segments: coalesce_segments(
              parse_with_default(line.prompt.to_s, line.prompt_color) +
                parse_with_default(line.command.to_s, line.command_color)
            ),
            selected: line.selected
          }
        end

        next rendered_lines unless line.output

        line.output.to_s.split("\n", -1).each do |output_line|
          rendered_lines << { segments: coalesce_segments(parse_with_default(output_line, line.output_color)), selected: line.selected }
        end
        rendered_lines
      end
    end

    def parse_with_default(text, default_color)
      @ansi_parser.parse(expand_tabs(text)).map do |segment|
        RenderSegment.from_segment(segment, default_color: default_color)
      end
    end

    def coalesce_segments(segments)
      RenderSegment.coalesce(segments)
    end

    def expand_tabs(text)
      text.to_s.gsub("\t", " " * config.window[:tab_width])
    end

    def create_image(lines, output_path, scale:, shadow:, transparent:)
      geometry = build_geometry(lines, scale: scale, shadow: shadow)

      return create_cached_content_image(geometry, output_path, transparent: transparent) if @chrome_cache

      create_full_image(geometry, output_path, transparent: transparent)
    end

    def create_svg_image(lines, output_path, scale:, shadow:, transparent:)
      SvgRasterWrapper.write(output_path) { |png_path| create_image(lines, png_path, scale: scale, shadow: shadow, transparent: transparent) }
    end

    def build_geometry(lines, scale:, shadow:)
      geometry_builder.build(lines, scale: scale, shadow: shadow)
    end

    def create_full_image(geometry, output_path, transparent:)
      ImageMagickCommandBuilder.convert do |convert|
        convert.size "#{geometry[:canvas_width]}x#{geometry[:canvas_height]}"
        convert << canvas_background(transparent)
        draw_chrome(convert, geometry, transparent: transparent)
        draw_content(convert, geometry)
        finish_image(convert, output_path)
      end
    end

    def create_cached_content_image(geometry, output_path, transparent:)
      base_path = @chrome_cache.fetch(geometry, transparent: transparent) do |path|
        create_chrome_image(geometry, path, transparent: transparent)
      end

      ImageMagickCommandBuilder.convert do |convert|
        convert << base_path
        draw_content(convert, geometry)
        finish_image(convert, output_path)
      end
    end

    def create_chrome_image(geometry, output_path, transparent:)
      ImageMagickCommandBuilder.convert do |convert|
        convert.size "#{geometry[:canvas_width]}x#{geometry[:canvas_height]}"
        convert << canvas_background(transparent)
        draw_chrome(convert, geometry, transparent: transparent)
        convert << output_path
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
      convert << ImageMagickCommandBuilder.output_path(output_path, format: File.extname(output_path).delete_prefix("."))
    end

    def canvas_background(transparent)
      gradient = config.window[:background_gradient]
      return "xc:transparent" if transparent
      return "gradient:#{gradient[0]}-#{gradient[1]}" if gradient.is_a?(Array) && gradient.size == 2

      "xc:#{theme.colors[:background]}"
    end

    def geometry_builder
      @geometry_builder ||= RenderGeometry.new(config: config, theme: theme)
    end
  end
end
