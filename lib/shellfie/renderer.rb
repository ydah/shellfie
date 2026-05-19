# frozen_string_literal: true

require "mini_magick"
require_relative "ansi_parser"
require_relative "dependency_checker"
require_relative "font_resolver"
require_relative "format_resolver"
require_relative "output_writer"
require_relative "raster_painter"
require_relative "render_chrome_cache"
require_relative "render_geometry"
require_relative "render_segment"
require_relative "svg_raster_wrapper"
require_relative "theme_registry"

module Shellfie
  class Renderer
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

      raster_painter.paint(geometry, output_path, transparent: transparent)
    end

    def create_svg_image(lines, output_path, scale:, shadow:, transparent:)
      SvgRasterWrapper.write(output_path) { |png_path| create_image(lines, png_path, scale: scale, shadow: shadow, transparent: transparent) }
    end

    def build_geometry(lines, scale:, shadow:)
      geometry_builder.build(lines, scale: scale, shadow: shadow)
    end

    def escape_text(text)
      raster_painter.send(:escape_text, text)
    end

    def geometry_builder
      @geometry_builder ||= RenderGeometry.new(config: config, theme: theme)
    end

    def raster_painter
      @raster_painter ||= RasterPainter.new(
        config: config,
        theme: theme,
        font_resolver: font_resolver,
        chrome_cache: @chrome_cache
      )
    end
  end
end
