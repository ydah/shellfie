# frozen_string_literal: true

require "mini_magick"
require_relative "ansi_parser"
require_relative "dependency_checker"
require_relative "font_resolver"
require_relative "line_layout"
require_relative "output_writer"
require_relative "rendering/text_painter"
require_relative "rendering/window_chrome"
require_relative "theme_registry"

module Shellfie
  class Renderer
    include Rendering::TextPainter
    include Rendering::WindowChrome

    attr_reader :config, :theme, :font_resolver

    def initialize(config)
      @config = config
      @theme = ThemeRegistry.build(config)
      @ansi_parser = AnsiParser.new(state_mode: config.window[:ansi_state] || :persistent)
      @font_resolver = FontResolver.new(-> { imagemagick_command })
    end

    def render(output_path, scale: 1, shadow: true, transparent: false, format: nil)
      check_dependencies!
      lines = build_lines
      extension = output_format(output_path, format)
      OutputWriter.write(output_path, extension: extension) do |temporary_path|
        create_image(lines, temporary_path, scale: scale, shadow: shadow, transparent: transparent)
      end
    rescue MiniMagick::Error => e
      raise RenderError.new("ImageMagick render failed: #{e.message}", category: :render)
    end

    def estimate(scale: 1, shadow: true)
      geometry = build_geometry(build_lines, scale: scale, shadow: shadow)
      geometry.slice(:canvas_width, :canvas_height, :scaled_width, :scaled_height)
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
            segments: parse_with_default(line.prompt.to_s, line.prompt_color) +
              parse_with_default(line.command.to_s, line.command_color),
            selected: line.selected
          }
        end

        next rendered_lines unless line.output

        line.output.to_s.split("\n", -1).each do |output_line|
          rendered_lines << { segments: parse_with_default(output_line, line.output_color), selected: line.selected }
        end
        rendered_lines
      end
    end

    def parse_with_default(text, default_color)
      @ansi_parser.parse(expand_tabs(text)).map do |segment|
        segment.foreground ||= default_color
        segment
      end
    end

    def expand_tabs(text)
      text.to_s.gsub("\t", " " * config.window[:tab_width])
    end

    def create_image(lines, output_path, scale:, shadow:, transparent:)
      geometry = build_geometry(lines, scale: scale, shadow: shadow)

      MiniMagick.convert do |convert|
        convert.size "#{geometry[:canvas_width]}x#{geometry[:canvas_height]}"
        convert << canvas_background(transparent)

        draw_shadow(convert, geometry) if geometry[:shadow]
        draw_window(convert, geometry, transparent: transparent)
        draw_title_bar(convert, geometry) unless config.headless
        draw_content(convert, geometry)

        if config.window[:trim]
          convert.trim
          convert << "+repage"
        end

        convert << output_path
      end
    end

    def build_geometry(lines, scale:, shadow:)
      decoration = theme.window_decoration
      font_config = theme.font
      padding = config.window[:padding]
      width = config.window[:width]
      font_size = font_config[:size]
      line_height = font_size * font_config[:line_height]
      title_bar_height = config.headless ? 0 : decoration[:title_bar_height]
      content_width = [width - (padding * 2), 1].max
      display_lines = line_layout.prepare(
        lines,
        content_width: content_width,
        font_size: font_size,
        title_bar_height: title_bar_height,
        padding: padding,
        line_height: line_height
      )
      content_height = [display_lines.size, 1].max * line_height + padding * 2
      total_height = title_bar_height + content_height
      exact_size = config.window[:exact_size]
      shadow_enabled = shadow && !exact_size
      margin = exact_size ? 0 : scaled_margin(scale, shadow_enabled)

      geometry = {
        lines: display_lines,
        font_config: font_config,
        width: width,
        height: total_height,
        padding: padding,
        line_height: line_height,
        font_size: font_size,
        title_bar_height: title_bar_height,
        radius: config.headless ? 0 : decoration[:corner_radius],
        scale: scale,
        scaled_width: (width * scale).to_i,
        scaled_height: (total_height * scale).ceil,
        scaled_padding: (padding * scale).to_i,
        scaled_line_height: (line_height * scale).ceil,
        scaled_font_size: (font_size * scale).to_i,
        scaled_title_bar: (title_bar_height * scale).to_i,
        scaled_radius: ((config.headless ? 0 : decoration[:corner_radius]) * scale).to_i,
        margin: margin,
        canvas_width: (width * scale).to_i + margin * 2,
        canvas_height: (total_height * scale).ceil + margin * 2,
        shadow: shadow_enabled
      }
      validate_pixel_limit!(geometry)
      geometry
    end

    def line_layout
      @line_layout ||= LineLayout.new(config)
    end

    def scaled_margin(scale, shadow)
      configured = config.window[:margin]
      return (configured * scale).to_i if configured
      return 0 if config.headless && !shadow
      return (10 * scale).to_i unless shadow

      shadow_config = theme.window_decoration[:shadow]
      blur = shadow_config[:blur].to_i
      offset_x = shadow_config[:offset_x].to_i.abs
      offset_y = shadow_config[:offset_y].to_i.abs
      (([blur, offset_x, offset_y].max + 10) * scale).to_i
    end

    def canvas_background(transparent)
      gradient = config.window[:background_gradient]
      return "xc:transparent" if transparent
      return "gradient:#{gradient[0]}-#{gradient[1]}" if gradient.is_a?(Array) && gradient.size == 2

      "xc:#{theme.colors[:background]}"
    end

    def output_format(output_path, format)
      return format if format
      return "png" if output_path == "-"

      ext = File.extname(output_path).delete_prefix(".")
      ext.empty? ? "png" : ext
    end

    def validate_pixel_limit!(geometry)
      pixels = geometry[:canvas_width] * geometry[:canvas_height]
      return if pixels <= config.limits[:max_pixels]

      raise ResourceLimitError, "Estimated image is too large (#{pixels} pixels, max #{config.limits[:max_pixels]})"
    end
  end
end
