# frozen_string_literal: true

require_relative "shellfie/version"
require_relative "shellfie/errors"
require_relative "shellfie/config"
require_relative "shellfie/parser"
require_relative "shellfie/ansi_parser"

module Shellfie
  autoload :AnimationFrameBuilder, File.expand_path("shellfie/animation_frame_builder", __dir__)
  autoload :AnimationScrollEasing, File.expand_path("shellfie/animation_scroll_easing", __dir__)
  autoload :AnimationTimeline, File.expand_path("shellfie/animation_timeline", __dir__)
  autoload :CLI, File.expand_path("shellfie/cli", __dir__)
  autoload :GifGenerator, File.expand_path("shellfie/gif_generator", __dir__)
  autoload :GifPalette, File.expand_path("shellfie/gif_palette", __dir__)
  autoload :ImageMagickCommandBuilder, File.expand_path("shellfie/image_magick_command_builder", __dir__)
  autoload :RenderChromeCache, File.expand_path("shellfie/render_chrome_cache", __dir__)
  autoload :Renderer, File.expand_path("shellfie/renderer", __dir__)

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
      { config: config.to_h, theme: config.theme, geometry: geometry, fonts: Renderer.new(config).font_info }
    end
  end
end
