# frozen_string_literal: true

module Shellfie
  class Error < StandardError
    attr_reader :category, :context

    def initialize(message = nil, category: nil, context: {})
      @category = category
      @context = context.freeze
      super(message)
    end
  end

  class ConfigError < Error; end
  class ParseError < ConfigError; end
  class ValidationError < ConfigError; end
  class ResourceLimitError < ConfigError; end

  class RenderError < Error; end
  class FontError < RenderError; end
  class ImageError < RenderError; end

  class DependencyError < Error; end
  class FileSystemError < Error; end
  class ExecutionError < Error; end
end
