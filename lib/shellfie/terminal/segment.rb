# frozen_string_literal: true

module Shellfie
  module Terminal
    Segment = Struct.new(
      :text,
      :foreground,
      :background,
      :bold,
      :italic,
      :underline,
      :underline_style,
      :underline_color,
      :dim,
      :reverse,
      :strikethrough,
      :overline,
      :blink,
      :conceal,
      :link,
      keyword_init: true
    )
  end
end
