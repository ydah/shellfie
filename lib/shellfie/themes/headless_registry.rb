# frozen_string_literal: true

require_relative 'data'

module Shellfie
  module Themes
    module HeadlessRegistry
      VARIANTS = {
        'plain' => {
          window_decoration: {
            title_bar_height: 0,
            corner_radius: 0,
            button_size: 0,
            button_spacing: 0
          },
          button_colors: [],
          button_style: :none,
          buttons_position: :left,
          title_alignment: :left
        }
      }.freeze

      class << self
        def apply(theme, variant: 'plain')
          settings = VARIANTS.fetch(variant)
          Data.new(
            name: theme.name,
            colors: theme.colors,
            window_decoration: Data.deep_merge(theme.window_decoration, settings[:window_decoration]),
            button_colors: settings[:button_colors],
            buttons_position: settings[:buttons_position],
            button_style: settings[:button_style],
            font: theme.font,
            title_alignment: settings[:title_alignment]
          )
        end

        def available_variants
          VARIANTS.keys
        end
      end
    end
  end
end
