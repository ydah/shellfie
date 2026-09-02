# frozen_string_literal: true

module Shellfie
  class RenderSegment
    ATTRIBUTES = %i[
      foreground background bold italic underline underline_style underline_color dim reverse strikethrough overline blink conceal link
    ].freeze

    attr_reader :text, :foreground, :background, :bold, :italic, :underline, :underline_style, :underline_color,
                :dim, :reverse, :strikethrough, :overline, :blink, :conceal, :link

    def self.from_segment(segment, default_color:)
      new(
        text: segment.text.to_s,
        foreground: segment.foreground || default_color,
        background: segment.background,
        bold: segment.bold,
        italic: segment.italic,
        underline: segment.underline,
        underline_style: segment.underline_style,
        underline_color: segment.underline_color,
        dim: segment.dim,
        reverse: segment.reverse,
        strikethrough: segment.strikethrough,
        overline: segment.overline,
        blink: segment.blink,
        conceal: segment.conceal,
        link: segment.link
      )
    end

    def self.copy(segment, text)
      new(**ATTRIBUTES.each_with_object(text: text.dup) do |attribute, values|
        values[attribute] = segment.public_send(attribute)
      end)
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

    def initialize(text:, foreground: nil, background: nil, bold: false, italic: false, underline: false,
                   underline_style: nil, underline_color: nil, dim: false, reverse: false, strikethrough: false,
                   overline: false, blink: false, conceal: false, link: nil)
      @text = text
      @foreground = foreground
      @background = background
      @bold = bold
      @italic = italic
      @underline = underline
      @underline_style = underline_style
      @underline_color = underline_color
      @dim = dim
      @reverse = reverse
      @strikethrough = strikethrough
      @overline = overline
      @blink = blink
      @conceal = conceal
      @link = link
      freeze
    end

    def same_style?(other)
      ATTRIBUTES.all? { |attribute| public_send(attribute) == other.public_send(attribute) }
    end
  end
end
