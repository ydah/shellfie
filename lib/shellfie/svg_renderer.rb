# frozen_string_literal: true

require "cgi/escape"
require_relative "text_metrics"

module Shellfie
  class SvgRenderer
    def initialize(config:, theme:)
      @config = config
      @theme = theme
    end

    def render(geometry, output_path, transparent: false)
      File.write(output_path, to_svg(geometry, transparent: transparent))
    end

    def to_svg(geometry, transparent: false)
      document(geometry, transparent: transparent)
    end

    private

    attr_reader :config, :theme

    def document(geometry, transparent:)
      <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="#{geometry[:canvas_width]}" height="#{geometry[:canvas_height]}" viewBox="0 0 #{geometry[:canvas_width]} #{geometry[:canvas_height]}" role="img" aria-labelledby="shellfie-title shellfie-description">
          <title id="shellfie-title">#{escape(config.title)}</title>
          <desc id="shellfie-description">Terminal session rendered by Shellfie</desc>
          #{definitions(geometry)}
          #{canvas(geometry, transparent)}
          #{window(geometry)}
          #{title_bar(geometry) unless config.headless}
          #{content(geometry)}
        </svg>
      SVG
    end

    def definitions(geometry)
      gradient = config.window[:background_gradient]
      gradient_definition = if gradient
                              <<~SVG
                                <linearGradient id="background" x1="0" y1="0" x2="0" y2="1">
                                  <stop offset="0" stop-color="#{escape(gradient[0])}"/>
                                  <stop offset="1" stop-color="#{escape(gradient[1])}"/>
                                </linearGradient>
                              SVG
                            end
      shadow = theme.window_decoration[:shadow]
      shadow_definition = if geometry[:shadow]
                            <<~SVG
                              <filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">
                                <feDropShadow dx="#{shadow[:offset_x] * geometry[:scale]}" dy="#{shadow[:offset_y] * geometry[:scale]}" stdDeviation="#{shadow[:blur] * geometry[:scale] / 2.0}" flood-color="#{escape(shadow[:color])}"/>
                              </filter>
                            SVG
                          end
      <<~SVG
        <defs>
          <style>@keyframes shellfie-blink { 50% { opacity: 0; } } .blink { animation: shellfie-blink 1s step-end infinite; } @media (prefers-reduced-motion: reduce) { .blink { animation: none; } }</style>
          #{gradient_definition}
          #{shadow_definition}
          <clipPath id="content-clip"><rect x="#{content_x(geometry)}" y="#{content_y(geometry)}" width="#{content_width(geometry)}" height="#{content_height(geometry)}"/></clipPath>
        </defs>
      SVG
    end

    def canvas(geometry, transparent)
      return "" if transparent

      fill = config.window[:background_gradient] ? "url(#background)" : theme.colors[:background]
      %(<rect width="100%" height="100%" fill="#{escape(fill)}"/>)
    end

    def window(geometry)
      attrs = [
        %(x="#{geometry[:margin]}"), %(y="#{geometry[:margin]}"), %(width="#{geometry[:scaled_width]}"),
        %(height="#{geometry[:scaled_height]}"), %(rx="#{geometry[:scaled_radius]}"),
        %(fill="#{escape(theme.colors[:background])}"), %(fill-opacity="#{config.window[:opacity]}")
      ]
      attrs << %(stroke="#{escape(theme.colors[:border])}") if theme.colors[:border]
      attrs << %(filter="url(#shadow)") if geometry[:shadow]
      "<rect #{attrs.join(" ")}/>"
    end

    def title_bar(geometry)
      margin = geometry[:margin]
      width = geometry[:scaled_width]
      height = geometry[:scaled_title_bar]
      radius = geometry[:scaled_radius]
      separator = theme.colors[:title_bar_border]
      <<~SVG
        <g>
          <path d="M #{margin + radius} #{margin} H #{margin + width - radius} Q #{margin + width} #{margin} #{margin + width} #{margin + radius} V #{margin + height} H #{margin} V #{margin + radius} Q #{margin} #{margin} #{margin + radius} #{margin} Z" fill="#{escape(theme.colors[:title_bar])}"/>
          #{%(<line x1="#{margin}" y1="#{margin + height}" x2="#{margin + width}" y2="#{margin + height}" stroke="#{escape(separator)}"/>) if separator}
          #{buttons(geometry)}
          #{title(geometry)}
        </g>
      SVG
    end

    def buttons(geometry)
      return windows_buttons(geometry) if theme.button_style == :icons

      scale = geometry[:scale]
      size = theme.window_decoration[:button_size] * scale
      spacing = (theme.window_decoration[:button_spacing] + theme.window_decoration[:button_size]) * scale
      y = geometry[:margin] + geometry[:scaled_title_bar] / 2
      start_x = theme.buttons_position == :left ? geometry[:margin] + 16 * scale : geometry[:margin] + geometry[:scaled_width] - 16 * scale - size * 2 - spacing * 2
      theme.button_colors.each_with_index.map do |color, index|
        %(<circle cx="#{start_x + index * spacing}" cy="#{y}" r="#{size / 2.0}" fill="#{escape(color)}" stroke="rgba(0,0,0,0.18)"/>)
      end.join("\n")
    end

    def windows_buttons(geometry)
      scale = geometry[:scale]
      button_width = (theme.window_decoration[:button_width] || 46) * scale
      start_x = geometry[:margin] + geometry[:scaled_width] - button_width * 3
      y = geometry[:margin] + geometry[:scaled_title_bar] / 2
      size = 5 * scale
      color = escape(theme.colors[:title_text])
      [
        %(<line x1="#{start_x + button_width / 2 - size}" y1="#{y}" x2="#{start_x + button_width / 2 + size}" y2="#{y}" stroke="#{color}"/>),
        %(<rect x="#{start_x + button_width * 1.5 - size}" y="#{y - size}" width="#{size * 2}" height="#{size * 2}" fill="none" stroke="#{color}"/>),
        %(<path d="M #{start_x + button_width * 2.5 - size} #{y - size} L #{start_x + button_width * 2.5 + size} #{y + size} M #{start_x + button_width * 2.5 + size} #{y - size} L #{start_x + button_width * 2.5 - size} #{y + size}" stroke="#{color}"/>)
      ].join("\n")
    end

    def title(geometry)
      font_size = geometry[:scaled_font_size]
      text = escape(config.title)
      x = geometry[:margin] + geometry[:scaled_width] / 2
      y = geometry[:margin] + geometry[:scaled_title_bar] / 2 + font_size * 0.35
      anchor = "middle"
      if theme.title_alignment == :left
        x = geometry[:margin] + 16 * geometry[:scale]
        anchor = "start"
      elsif theme.title_alignment == :right
        x = geometry[:margin] + geometry[:scaled_width] - 16 * geometry[:scale]
        anchor = "end"
      end
      %(<text x="#{x}" y="#{y}" text-anchor="#{anchor}" #{font_attributes(geometry[:font_config], font_size)} fill="#{escape(theme.colors[:title_text])}">#{text}</text>)
    end

    def content(geometry)
      y = content_y(geometry) - (geometry[:scroll_offset] * geometry[:scaled_line_height]).round
      lines = geometry[:lines].each_with_index.map do |line, index|
        line_svg(line, geometry, y + index * geometry[:scaled_line_height])
      end
      %(<g clip-path="url(#content-clip)">#{lines.join("\n")}</g>)
    end

    def line_svg(line, geometry, top)
      selected = if line[:selected]
                   %(<rect x="#{content_x(geometry)}" y="#{top}" width="#{content_width(geometry)}" height="#{geometry[:scaled_line_height]}" fill="#{escape(theme.colors[:selection])}"/>)
                 end
      x = content_x(geometry)
      segments = line[:segments].map do |segment|
        width = TextMetrics.pixel_width(segment.text, geometry[:scaled_font_size])
        svg = segment_svg(segment, x, top, width, geometry)
        x += width
        svg
      end
      [selected, *segments].compact.join("\n")
    end

    def segment_svg(segment, x, top, width, geometry)
      foreground = segment.foreground ? theme.color_for(segment.foreground) : theme.colors[:foreground]
      background = segment.background ? theme.color_for(segment.background) : nil
      foreground, background = background || theme.colors[:background], foreground if segment.reverse
      opacity = if segment.conceal
                  %( fill-opacity="0")
                elsif segment.dim
                  %( fill-opacity="0.6")
                else
                  ""
                end
      decoration = []
      decoration << "underline" if segment.underline
      decoration << "line-through" if segment.strikethrough
      decoration << "overline" if segment.overline
      background_svg = %(<rect x="#{x}" y="#{top}" width="#{width}" height="#{geometry[:scaled_line_height]}" fill="#{escape(background)}"/>) if background
      underline_style = segment.underline_style == :curly ? :wavy : segment.underline_style
      decoration_style = %( text-decoration-style="#{underline_style}") if underline_style && underline_style != :single
      decoration_color = %( text-decoration-color="#{escape(theme.color_for(segment.underline_color))}") if segment.underline_color
      blink = segment.blink ? %( class="blink") : ""
      text = %(<text x="#{x}" y="#{top + geometry[:scaled_font_size]}" xml:space="preserve" #{font_attributes(geometry[:font_config], geometry[:scaled_font_size], segment)} fill="#{escape(foreground)}"#{opacity}#{blink}#{%( text-decoration="#{decoration.join(" ")}") unless decoration.empty?}#{decoration_style}#{decoration_color}>#{escape(segment.text)}</text>)
      [background_svg, text].compact.join("\n")
    end

    def font_attributes(font, size, segment = nil)
      family = [font[:family], font[:fallback_family], font[:emoji_family]].compact.join(", ")
      attrs = [%(font-family="#{escape(family)}"), %(font-size="#{size}")]
      attrs << %(font-weight="700") if segment&.bold
      attrs << %(font-style="italic") if segment&.italic
      attrs.join(" ")
    end

    def content_x(geometry)
      geometry[:margin] + geometry[:scaled_padding]
    end

    def content_y(geometry)
      geometry[:margin] + geometry[:scaled_title_bar] + geometry[:scaled_padding]
    end

    def content_width(geometry)
      [geometry[:scaled_width] - geometry[:scaled_padding] * 2, 1].max
    end

    def content_height(geometry)
      [geometry[:scaled_height] - geometry[:scaled_title_bar] - geometry[:scaled_padding] * 2, 1].max
    end

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
