# frozen_string_literal: true

require "mini_magick"
require_relative "ansi_parser"
require_relative "themes/base"
require_relative "themes/macos"
require_relative "themes/ubuntu"
require_relative "themes/windows_terminal"

module Shellfie
  class Renderer
    THEMES = {
      "macos" => Themes::MacOS,
      "ubuntu" => Themes::Ubuntu,
      "windows" => Themes::WindowsTerminal
    }.freeze

    attr_reader :config, :theme

    def initialize(config)
      @config = config
      @theme = load_theme(config.theme)
      @ansi_parser = AnsiParser.new
    end

    def render(output_path, scale: 1, shadow: true, transparent: false)
      check_dependencies!

      lines = build_lines
      create_image(lines, output_path, scale: scale, shadow: shadow, transparent: transparent)
      output_path
    end

    private

    def load_theme(name)
      klass = THEMES[name] || THEMES["macos"]
      klass.new
    end

    def check_dependencies!
      result = `which magick 2>/dev/null || which convert 2>/dev/null`.strip
      if result.empty?
        raise DependencyError, <<~MSG
          ImageMagick not found
            → Please install ImageMagick: brew install imagemagick
            → Or visit: https://imagemagick.org/script/download.php
        MSG
      end
    end

    def build_lines
      config.lines.flat_map do |line|
        result = []
        if line.prompt
          prompt_segments = @ansi_parser.parse(line.prompt)
          command_segments = line.command ? @ansi_parser.parse(line.command) : []
          result << { segments: prompt_segments + command_segments }
        end
        if line.output
          line.output.split("\n").each do |output_line|
            result << { segments: @ansi_parser.parse(output_line) }
          end
        end
        result
      end
    end

    def create_image(lines, output_path, scale:, shadow:, transparent:)
      decoration = theme.window_decoration
      font_config = config.font.is_a?(Hash) ? config.font : theme.font
      padding = config.window[:padding] || 20
      width = config.window[:width] || 600
      line_height = (font_config[:size] || 14) * (font_config[:line_height] || 1.4)
      title_bar_height = config.headless ? 0 : decoration[:title_bar_height]

      content_height = lines.size * line_height + padding * 2
      total_height = title_bar_height + content_height
      corner_radius = decoration[:corner_radius]

      scaled_width = (width * scale).to_i
      scaled_height = (total_height * scale).to_i
      scaled_padding = (padding * scale).to_i
      scaled_title_bar = (title_bar_height * scale).to_i
      scaled_line_height = (line_height * scale).to_i
      scaled_font_size = ((font_config[:size] || 14) * scale).to_i
      scaled_radius = (corner_radius * scale).to_i

      margin = (50 * scale).to_i
      canvas_width = scaled_width + margin * 2
      canvas_height = scaled_height + margin * 2

      MiniMagick.convert do |convert|
        convert.size "#{canvas_width}x#{canvas_height}"
        convert << "xc:transparent"

        if shadow
          convert.fill "rgba(0,0,0,0.3)"
          shadow_offset = (10 * scale).to_i
          convert.draw "roundrectangle #{margin + shadow_offset},#{margin + shadow_offset} " \
                       "#{margin + scaled_width - 1 + shadow_offset},#{margin + scaled_height - 1 + shadow_offset} " \
                       "#{scaled_radius},#{scaled_radius}"
          convert.blur "0x#{(15 * scale).to_i}"
        end

        convert.fill theme.colors[:background]
        convert.draw "roundrectangle #{margin},#{margin} " \
                     "#{margin + scaled_width - 1},#{margin + scaled_height - 1} " \
                     "#{scaled_radius},#{scaled_radius}"

        unless config.headless
          convert.fill theme.colors[:title_bar]
          title_y2 = margin + scaled_title_bar - 1
          convert.draw "roundrectangle #{margin},#{margin} " \
                       "#{margin + scaled_width - 1},#{title_y2} " \
                       "#{scaled_radius},#{scaled_radius}"
          convert.fill theme.colors[:title_bar]
          convert.draw "rectangle #{margin},#{margin + scaled_radius} " \
                       "#{margin + scaled_width - 1},#{title_y2}"

          button_x, button_y = button_positions(margin, scaled_title_bar, scale)
          button_radius = ((theme.window_decoration[:button_size] / 2) * scale).to_i

          theme.button_colors.each_with_index do |color, i|
            spacing = ((theme.window_decoration[:button_spacing] + theme.window_decoration[:button_size]) * scale).to_i
            bx = button_x + i * spacing
            convert.fill color
            convert.draw "circle #{bx},#{button_y} #{bx + button_radius},#{button_y}"
          end

          convert.fill theme.colors[:title_text]
          convert.pointsize scaled_font_size
          title_y = margin + scaled_title_bar / 2 + scaled_font_size / 3
          title_x = margin + scaled_width / 2
          convert.gravity "NorthWest"
          convert.draw "text #{title_x - config.title.to_s.length * scaled_font_size / 4},#{title_y - scaled_font_size} '#{escape_text(config.title.to_s)}'"
        end

        content_y = margin + scaled_title_bar + scaled_padding
        lines.each_with_index do |line, idx|
          y = content_y + idx * scaled_line_height + scaled_font_size
          x = margin + scaled_padding
          draw_line_segments(convert, line[:segments], x, y, scaled_font_size, font_config)
        end

        convert << output_path
      end
    end

    def button_positions(margin, title_bar_height, scale)
      button_size = (theme.window_decoration[:button_size] * scale).to_i
      scaled_width = ((config.window[:width] || 600) * scale).to_i

      if theme.buttons_position == :left
        x = margin + (16 * scale).to_i
      else
        x = margin + scaled_width - (16 * scale).to_i - button_size * 3
      end
      y = margin + title_bar_height / 2

      [x, y]
    end

    def draw_line_segments(convert, segments, x, y, font_size, font_config)
      current_x = x

      segments.each do |segment|
        color = segment.foreground ? theme.color_for(segment.foreground) : theme.colors[:foreground]
        text = escape_text(segment.text)

        next if text.empty?

        convert.fill color
        convert.pointsize font_size

        convert.draw "text #{current_x},#{y} '#{text}'"

        char_width = font_size * 0.6
        current_x += (segment.text.length * char_width).to_i
      end
    end

    def escape_text(text)
      text.to_s.gsub("'", "\\\\'").gsub("\\", "\\\\\\\\")
    end
  end
end
