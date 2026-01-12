# frozen_string_literal: true

module Shellfie
  class Config
    DEFAULTS = {
      theme: "macos",
      window: {
        width: 600,
        padding: 20,
        opacity: 1.0
      },
      font: {
        family: "Monaco",
        size: 14,
        line_height: 1.4
      },
      animation: {
        typing_speed: 80,
        command_delay: 500,
        cursor_blink: true,
        loop: false
      }
    }.freeze

    attr_reader :theme, :title, :window, :font, :lines, :animation, :frames, :headless

    def initialize(options = {})
      merged = merge_defaults(options)
      @theme = merged[:theme]
      @title = merged[:title] || "Terminal"
      @window = merged[:window]
      @font = merged[:font]
      @lines = merged[:lines] || []
      @animation = merged[:animation]
      @frames = merged[:frames] || []
      @headless = options[:headless] || false
    end

    def static?
      @frames.empty?
    end

    def animated?
      !static?
    end

    private

    def merge_defaults(options)
      result = {}
      DEFAULTS.each do |key, value|
        result[key] = if value.is_a?(Hash) && options[key].is_a?(Hash)
                        value.merge(options[key])
                      else
                        options.key?(key) ? options[key] : value
                      end
      end
      result[:title] = options[:title]
      result[:lines] = options[:lines]
      result[:frames] = options[:frames]
      result
    end
  end
end
