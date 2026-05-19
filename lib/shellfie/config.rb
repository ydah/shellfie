# frozen_string_literal: true

require_relative "config_validation"
require_relative "config_defaults"
require_relative "errors"
require_relative "theme_registry"

module Shellfie
  class Config
    include ConfigValidation

    VALID_THEMES = ThemeRegistry.available_themes.freeze
    VALID_OVERFLOW_MODES = %w[clip wrap scroll].freeze
    VALID_CURSOR_STYLES = %w[block bar underline].freeze
    VALID_PALETTES = %w[global adaptive theme].freeze
    VALID_SCROLL_EASINGS = %w[linear ease_in ease_out ease_in_out].freeze

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

      def normalize_keys(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), result|
            normalized_key = key.is_a?(String) ? key.to_sym : key
            result[normalized_key] = normalize_keys(nested_value)
          end
        when Array
          value.map { |nested_value| normalize_keys(nested_value) }
        else
          value
        end
      end
    end

    DEFAULTS = deep_freeze(deep_dup(ConfigDefaults::VALUES))

    attr_reader :version, :theme, :window_theme, :color_scheme, :colors, :window_decoration, :title, :window, :font,
                :lines, :animation, :frames, :headless, :cursor, :limits

    def initialize(options = {})
      options = self.class.normalize_keys(options)
      merged = merge_defaults(options)
      @version = merged[:version]
      @theme = merged[:theme]
      @window_theme = merged[:window_theme]
      @color_scheme = merged[:color_scheme]
      @colors = merged[:colors]
      @window_decoration = merged[:window_decoration]
      @title = merged[:title] || "Terminal"
      @window = merged[:window]
      @font = merged[:font]
      @lines = merged[:lines] || []
      @animation = merged[:animation]
      @frames = merged[:frames] || []
      @cursor = merged[:cursor]
      @limits = merged[:limits]
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

    def to_h
      {
        version: version,
        theme: theme,
        window_theme: window_theme,
        color_scheme: color_scheme,
        colors: colors,
        window_decoration: window_decoration,
        title: title,
        window: window,
        font: font,
        animation: animation,
        cursor: cursor,
        limits: limits,
        headless: headless,
        lines: lines.map(&:to_h),
        frames: frames.map(&:to_h)
      }
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
      @colors = self.class.deep_freeze(@colors)
      @window_decoration = self.class.deep_freeze(@window_decoration)
      @window = self.class.deep_freeze(@window)
      @font = self.class.deep_freeze(@font)
      @animation = self.class.deep_freeze(@animation)
      @cursor = self.class.deep_freeze(@cursor)
      @limits = self.class.deep_freeze(@limits)
      @lines = self.class.deep_freeze(@lines)
      @frames = self.class.deep_freeze(@frames)
      @title.freeze
      @theme.freeze
      @window_theme.freeze if @window_theme
      @color_scheme.freeze if @color_scheme
      freeze
    end
  end
end
