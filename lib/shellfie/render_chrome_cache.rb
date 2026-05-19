# frozen_string_literal: true

require "tempfile"

module Shellfie
  class RenderChromeCache
    def initialize
      @entries = {}
    end

    def fetch(geometry, transparent:)
      key = cache_key(geometry, transparent)
      return @entries[key].path if @entries.key?(key)

      temp = Tempfile.new(["shellfie-chrome", ".png"], binmode: true)
      temp.close
      yield temp.path
      @entries[key] = temp
      temp.path
    end

    def cleanup
      @entries.each_value do |temp|
        File.delete(temp.path) if File.exist?(temp.path)
        temp.close unless temp.closed?
      end
      @entries.clear
    end

    private

    def cache_key(geometry, transparent)
      [
        transparent,
        geometry.values_at(:canvas_width, :canvas_height, :scaled_width, :scaled_height, :scaled_title_bar, :margin,
          :shadow, :scaled_radius)
      ]
    end
  end
end
