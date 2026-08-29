# frozen_string_literal: true

require_relative "ansi_parser"
require_relative "render_segment"
require_relative "text_metrics"

module Shellfie
  class LineLayout
    attr_reader :visible_count

    def initialize(config)
      @config = config
    end

    def prepare(lines, content_width:, font_size:, title_bar_height:, padding:, line_height:)
      max_cells = [(content_width / (font_size * 0.6)).floor, 1].max
      mode = @config.window[:wrap] ? "wrap" : @config.window[:overflow]
      display_lines = lines.flat_map { |line| apply_overflow(line, max_cells, mode) }
      line_limit = vertical_line_limit(title_bar_height, padding, line_height)
      @visible_count = line_limit || display_lines.size
      render_limit = render_line_limit(line_limit)
      render_limit ? display_lines.last(render_limit) : display_lines
    end

    private

    def apply_overflow(line, max_cells, mode)
      return [line] if line[:segments].empty?

      case mode
      when "wrap"
        wrap_line(line, max_cells)
      when "scroll"
        [line.merge(segments: scroll_segments(line[:segments], max_cells))]
      else
        [line.merge(segments: clip_segments(line[:segments], max_cells))]
      end
    end

    def vertical_line_limit(title_bar_height, padding, line_height)
      limits = [@config.window[:visible_lines], @config.window[:max_lines]].compact
      [@config.window[:height], @config.window[:max_height]].compact.each do |height|
        available_height = height - title_bar_height - padding * 2
        limits << [(available_height / line_height).floor, 1].max
      end

      limits.empty? ? nil : limits.min
    end

    def render_line_limit(line_limit)
      return nil unless line_limit

      line_limit + (@config.window[:scroll_offset].to_f.positive? ? 1 : 0)
    end

    def wrap_line(line, max_cells)
      wrapped = [{ segments: [], selected: line[:selected] }]
      used_cells = 0

      line[:segments].each do |segment|
        TextMetrics.graphemes(segment.text).each do |char|
          width = TextMetrics.grapheme_width(char, ambiguous_width: ambiguous_width)
          if used_cells.positive? && used_cells + width > max_cells
            wrapped << { segments: [], selected: line[:selected] }
            used_cells = 0
          end

          append_segment_text(wrapped.last[:segments], segment, char)
          used_cells += width
        end
      end

      wrapped
    end

    def clip_segments(segments, max_cells)
      remaining = max_cells
      segments.each_with_object([]) do |segment, result|
        break result if remaining <= 0

        text = TextMetrics.take_cells(segment.text, remaining, ambiguous_width: ambiguous_width)
        next if text.empty?

        result << copy_segment(segment, text)
        remaining -= TextMetrics.cell_width(text, ambiguous_width: ambiguous_width)
      end
    end

    def scroll_segments(segments, max_cells)
      total_cells = segments.sum { |segment| TextMetrics.cell_width(segment.text, ambiguous_width: ambiguous_width) }
      return clip_segments(segments, max_cells) if total_cells <= max_cells

      cells_to_drop = total_cells - max_cells
      scrolled = []

      segments.each do |segment|
        segment_cells = TextMetrics.cell_width(segment.text, ambiguous_width: ambiguous_width)
        if cells_to_drop >= segment_cells
          cells_to_drop -= segment_cells
          next
        end

        text = cells_to_drop.positive? ? TextMetrics.drop_cells(segment.text, cells_to_drop, ambiguous_width: ambiguous_width) : segment.text
        cells_to_drop = 0
        scrolled << copy_segment(segment, text) unless text.empty?
      end

      clip_segments(scrolled, max_cells)
    end

    def append_segment_text(segments, source_segment, char)
      if segments.last && segment_style_key(segments.last) == segment_style_key(source_segment)
        segments.last.text << char
      else
        segments << copy_segment(source_segment, char)
      end
    end

    def copy_segment(segment, text)
      RenderSegment.copy(segment, text)
    end

    def segment_style_key(segment)
      [
        segment.foreground,
        segment.background,
        segment.bold,
        segment.italic,
        segment.underline,
        segment.underline_style,
        segment.underline_color,
        segment.dim,
        segment.reverse,
        segment.strikethrough,
        segment.overline,
        segment.blink,
        segment.conceal,
        segment.link
      ]
    end

    def ambiguous_width
      @config.window[:ambiguous_width]
    end
  end
end
