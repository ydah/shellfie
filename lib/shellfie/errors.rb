# frozen_string_literal: true

module Shellfie
  class Error < StandardError; end

  class ConfigError < Error; end
  class ParseError < ConfigError; end
  class ValidationError < ConfigError; end

  class RenderError < Error; end
  class FontError < RenderError; end
  class ImageError < RenderError; end

  class DependencyError < Error; end
end
