# frozen_string_literal: true

require "mini_magick"

module Shellfie
  class ImageMagickCommandBuilder
    class << self
      def convert(&block)
        MiniMagick.convert(&block)
      end

      def output_path(path, format:)
        format == "apng" ? "apng:#{path}" : path
      end
    end
  end
end
