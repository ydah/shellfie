# frozen_string_literal: true

module Shellfie
  class RenderSegment
    ATTRIBUTES = %i[
      foreground background bold italic underline dim reverse strikethrough overline
    ].freeze

    attr_reader :text, :foreground, :background, :bold, :italic, :underline, :dim, :reverse, :strikethrough, :overline

    def self.from_segment(segment, default_color:)
      new(
        text: segment.text.to_s,
        foreground: segment.foreground || default_color,
        background: segment.background,
        bold: segment.bold,
        italic: segment.italic,
        underline: segment.underline,
        dim: segment.dim,
        reverse: segment.reverse,
        strikethrough: segment.strikethrough,
        overline: segment.overline
      )
    end

    def self.copy(segment, text)
      new(**ATTRIBUTES.each_with_object(text: text.dup) { |attribute, values| values[attribute] = segment.public_send(attribute) })
    end

    def self.coalesce(segments)
      segments.each_with_object([]) do |segment, result|
        if result.last&.same_style?(segment)
          result[-1] = copy(result.last, result.last.text + segment.text)
        else
          result << segment
        end
      end
    end

    def initialize(text:, foreground: nil, background: nil, bold: false, italic: false, underline: false, dim: false,
                   reverse: false, strikethrough: false, overline: false)
      @text = text
      @foreground = foreground
      @background = background
      @bold = bold
      @italic = italic
      @underline = underline
      @dim = dim
      @reverse = reverse
      @strikethrough = strikethrough
      @overline = overline
      freeze
    end

    def same_style?(other)
      ATTRIBUTES.all? { |attribute| public_send(attribute) == other.public_send(attribute) }
    end
  end
end
