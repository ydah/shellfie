# frozen_string_literal: true

require 'mini_magick'
require_relative 'terminal/ansi_parser'
require_relative 'dependency_checker'
require_relative 'rendering/font_resolver'
require_relative 'rendering/format_resolver'
require_relative 'rendering/html_renderer'
require_relative 'output_writer'
require_relative 'rendering/raster_painter'
require_relative 'rendering/chrome_cache'
require_relative 'rendering/geometry'
require_relative 'rendering/segment'
require_relative 'rendering/svg_raster_wrapper'
require_relative 'rendering/svg_renderer'
require_relative 'themes/registry'

module Shellfie
  class Renderer
    attr_reader :config, :theme, :font_resolver

    def initialize(config, chrome_cache: nil)
      @config = config
      @chrome_cache = chrome_cache
      @theme = Themes::Registry.resolve(config)
      @ansi_parser = Terminal::ANSIParser.new(
        state_mode: config.window[:ansi_state] || :persistent,
        tab_width: config.window[:tab_width],
        osc_policy: config.window[:osc_policy],
        graphics_policy: config.window[:graphics_policy]
      )
      @font_resolver = Rendering::FontResolver.new(-> { imagemagick_command })
    end

    def render(output_path, scale: 1, shadow: true, transparent: false, format: nil, io: nil)
      extension = Rendering::FormatResolver.resolve(output_path, explicit: format, default: 'png')
      ensure_dependencies unless %w[svg html].include?(extension)
      lines = build_lines
      OutputWriter.write(output_path, extension: extension, io: io) do |temporary_path|
        render_method = { 'svg' => :write_svg, 'svg-raster' => :write_svg_raster, 'html' => :write_html }.fetch(
          extension, :write_raster_image
        )
        send(render_method, lines, temporary_path, scale: scale, shadow: shadow, transparent: transparent)
      end
    rescue MiniMagick::Error => e
      raise RenderError.new("ImageMagick render failed: #{e.message}", category: :render)
    end

    def estimate(scale: 1, shadow: true)
      geometry = build_geometry(build_lines, scale: scale, shadow: shadow)
      geometry.slice(:canvas_width, :canvas_height, :scaled_width, :scaled_height, :logical_width, :logical_height,
                     :scale)
    end

    def font_details
      font_resolver.details(theme.font)
    end

    private

    def ensure_dependencies
      DependencyChecker.configure_mini_magick
      DependencyChecker.ensure_imagemagick
    end

    def imagemagick_command
      @imagemagick_command ||= DependencyChecker.imagemagick_path.to_s
    end

    def build_lines
      config.lines.flat_map do |line|
        [command_line(line), *output_lines(line)].compact
      end
    end

    def command_line(line)
      return unless line.prompt || line.command

      segments = parse_with_default(line.prompt.to_s, line.prompt_color) +
                 parse_with_default(line.command.to_s, line.command_color)
      { segments: coalesce_segments(segments), selected: line.selected }
    end

    def output_lines(line)
      return [] unless line.output

      line.output.to_s.split("\n", -1).map do |output|
        { segments: coalesce_segments(parse_with_default(output, line.output_color)), selected: line.selected }
      end
    end

    def parse_with_default(text, default_color)
      @ansi_parser.parse(text).map do |segment|
        Rendering::Segment.from_terminal(segment, default_color: default_color)
      end
    end

    def coalesce_segments(segments)
      Rendering::Segment.coalesce(segments)
    end

    def write_raster_image(lines, output_path, scale:, shadow:, transparent:)
      geometry = build_geometry(lines, scale: scale, shadow: shadow)

      raster_painter.paint(geometry, output_path, transparent: transparent)
    end

    def write_svg(lines, output_path, scale:, shadow:, transparent:)
      geometry = build_geometry(lines, scale: scale, shadow: shadow)
      Rendering::SVGRenderer.new(config: config, theme: theme).render(geometry, output_path, transparent: transparent)
    end

    def write_svg_raster(lines, output_path, scale:, shadow:, transparent:)
      Rendering::SVGRasterWrapper.write(output_path) do |png_path|
        write_raster_image(lines, png_path, scale: scale, shadow: shadow, transparent: transparent)
      end
    end

    def write_html(lines, output_path, scale:, shadow:, transparent:)
      geometry = build_geometry(lines, scale: scale, shadow: shadow)
      Rendering::HTMLRenderer.new(config: config, theme: theme).render(geometry, output_path, transparent: transparent)
    end

    def build_geometry(lines, scale:, shadow:)
      geometry_builder.build(lines, scale: scale, shadow: shadow)
    end

    def escape_text(text)
      raster_painter.send(:escape_text, text)
    end

    def geometry_builder
      @geometry_builder ||= Rendering::Geometry.new(config: config, theme: theme)
    end

    def raster_painter
      @raster_painter ||= Rendering::RasterPainter.new(
        config: config,
        theme: theme,
        font_resolver: font_resolver,
        chrome_cache: @chrome_cache
      )
    end
  end
end
