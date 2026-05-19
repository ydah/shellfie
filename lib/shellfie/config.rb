# frozen_string_literal: true

require_relative "config_validation"
require_relative "errors"

module Shellfie
  class Config
    include ConfigValidation

    VALID_THEMES = %w[macos ubuntu windows].freeze
    VALID_OVERFLOW_MODES = %w[clip wrap scroll].freeze
    VALID_CURSOR_STYLES = %w[block bar underline].freeze

    class << self
      def deep_dup(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, nested_value), result| result[key] = deep_dup(nested_value) }
        when Array
          value.map { |nested_value| deep_dup(nested_value) }
        else
          value
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each_value { |nested_value| deep_freeze(nested_value) }
        when Array
          value.each { |nested_value| deep_freeze(nested_value) }
        end
        value.freeze
      end
    end

    DEFAULTS = deep_freeze({
      theme: "macos",
      window: {
        width: 600,
        padding: 20,
        opacity: 1.0,
        visible_lines: nil,
        max_lines: nil,
        max_height: nil,
        wrap: false,
        overflow: "clip",
        margin: nil,
        exact_size: false,
        trim: false,
        tab_width: 8,
        ansi_state: "persistent",
        background_gradient: nil
      },
      font: {
        family: "Monaco",
        size: 14,
        line_height: 1.4,
        fallback_family: nil,
        italic_family: nil,
        emoji_family: nil
      },
      animation: {
        typing_speed: 80,
        command_delay: 500,
        cursor_blink: true,
        loop: false,
        typing_jitter: 0.0,
        typing_chunk_size: 1,
        output_delay: 0,
        final_delay: 1_000,
        max_frames: nil,
        dither: true
      },
      cursor: {
        style: "block",
        color: nil
      }
    })

    attr_reader :theme, :title, :window, :font, :lines, :animation, :frames, :headless, :cursor

    def initialize(options = {})
      merged = merge_defaults(options)
      @theme = merged[:theme]
      @title = merged[:title] || "Terminal"
      @window = merged[:window]
      @font = merged[:font]
      @lines = merged[:lines] || []
      @animation = merged[:animation]
      @frames = merged[:frames] || []
      @cursor = merged[:cursor]
      @headless = merged[:headless] || false

      validate!
      freeze_state!
    end

    def static?
      @frames.empty?
    end

    def animated?
      !static?
    end

    private

    def merge_defaults(options)
      result = self.class.deep_dup(DEFAULTS)
      DEFAULTS.each do |key, value|
        next unless options.key?(key)

        result[key] = if value.is_a?(Hash) && options[key].is_a?(Hash)
                        result[key].merge(options[key])
                      else
                        self.class.deep_dup(options[key])
                      end
      end
      result[:title] = options[:title]
      result[:lines] = options[:lines]
      result[:frames] = options[:frames]
      result[:headless] = options[:headless] if options.key?(:headless)
      result
    end

    def freeze_state!
      @window = self.class.deep_freeze(@window)
      @font = self.class.deep_freeze(@font)
      @animation = self.class.deep_freeze(@animation)
      @cursor = self.class.deep_freeze(@cursor)
      @lines = self.class.deep_freeze(@lines)
      @frames = self.class.deep_freeze(@frames)
      @title.freeze
      @theme.freeze
      freeze
    end
  end
end
