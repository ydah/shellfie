# frozen_string_literal: true

require_relative "shellfie/version"
require_relative "shellfie/errors"
require_relative "shellfie/config"
require_relative "shellfie/parser"
require_relative "shellfie/ansi_parser"
require_relative "shellfie/renderer"
require_relative "shellfie/gif_generator"
require_relative "shellfie/cli"

module Shellfie
  class << self
    def parse(source)
      Parser.parse(source)
    end

    def validate(source)
      parse(source)
      true
    end

    def render(config_or_source, output:, animate: nil, scale: 1, shadow: true, transparent: false, format: nil)
      config = config_or_source.is_a?(Config) ? config_or_source : parse(config_or_source)
      animated = animate.nil? ? config.animated? : animate

      if animated
        GifGenerator.new(config).generate(output, scale: scale, shadow: shadow, transparent: transparent, format: format)
      else
        Renderer.new(config).render(output, scale: scale, shadow: shadow, transparent: transparent, format: format)
      end
    end

    def inspect_config(source, scale: 1, shadow: true)
      config = parse(source)
      geometry = Renderer.new(config).estimate(scale: scale, shadow: shadow)
      { config: config.to_h, theme: config.theme, geometry: geometry }
    end
  end
end
