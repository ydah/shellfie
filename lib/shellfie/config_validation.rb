# frozen_string_literal: true

module Shellfie
  module ConfigValidation
    def validate!
      validate_version!
      validate_theme!
      validate_window!
      validate_font!
      validate_animation!
      validate_cursor!
      validate_lines!
      validate_limits!
      validate_headless!
      validate_resource_limits!
    end

    private

    def validate_version!
      return if @version == 1

      raise ValidationError, "Unsupported config version '#{@version}'"
    end

    def validate_theme!
      return if ThemeRegistry.valid_theme?(@theme)

      raise ValidationError, "Invalid theme '#{@theme}'\n  → Available themes: #{ThemeRegistry.available_themes.join(", ")}"
    end

    def validate_window_theme!
      return if @window_theme.nil? || ThemeRegistry.valid_window_theme?(@window_theme)

      raise ValidationError, "Invalid window_theme '#{@window_theme}'"
    end

    def validate_color_scheme!
      return if ThemeRegistry.valid_color_scheme?(@color_scheme)

      raise ValidationError, "Invalid color_scheme '#{@color_scheme}'"
    end

    def validate_window!
      validate_window_theme!
      validate_color_scheme!
      validate_positive_integer!(@window[:width], "window.width")
      validate_non_negative_integer!(@window[:padding], "window.padding")
      %i[opacity scroll_offset].each { |key| validate_number_range!(@window[key], "window.#{key}", 0.0, 1.0) }
      validate_optional_positive_integer!(@window[:visible_lines], "window.visible_lines")
      validate_optional_positive_integer!(@window[:max_lines], "window.max_lines")
      validate_optional_positive_integer!(@window[:max_height], "window.max_height")
      validate_optional_non_negative_integer!(@window[:margin], "window.margin")
      validate_positive_integer!(@window[:tab_width], "window.tab_width")
      validate_boolean!(@window[:wrap], "window.wrap")
      validate_boolean!(@window[:exact_size], "window.exact_size")
      validate_boolean!(@window[:trim], "window.trim")
      validate_overflow!
      validate_ansi_state!
      validate_background_gradient!
      validate_minimum_width!
    end

    def validate_font!
      validate_optional_string!(@font[:family], "font.family")
      validate_optional_string!(@font[:fallback_family], "font.fallback_family")
      validate_optional_string!(@font[:italic_family], "font.italic_family")
      validate_optional_string!(@font[:emoji_family], "font.emoji_family")
      validate_positive_number!(@font[:size], "font.size")
      validate_positive_number!(@font[:line_height], "font.line_height")
    end

    def validate_animation!
      validate_non_negative_integer!(@animation[:typing_speed], "animation.typing_speed")
      validate_non_negative_integer!(@animation[:command_delay], "animation.command_delay")
      validate_number_range!(@animation[:typing_jitter], "animation.typing_jitter", 0.0, 1.0)
      validate_positive_integer!(@animation[:typing_chunk_size], "animation.typing_chunk_size")
      validate_non_negative_integer!(@animation[:output_delay], "animation.output_delay")
      validate_non_negative_integer!(@animation[:final_delay], "animation.final_delay")
      validate_optional_positive_integer!(@animation[:max_frames], "animation.max_frames")
      validate_boolean!(@animation[:cursor_blink], "animation.cursor_blink")
      validate_boolean!(@animation[:loop], "animation.loop")
      validate_boolean!(@animation[:dither], "animation.dither")
      validate_inclusion!(@animation[:palette], "animation.palette", self.class::VALID_PALETTES)
      validate_inclusion!(@animation[:scroll_easing], "animation.scroll_easing", self.class::VALID_SCROLL_EASINGS)
      validate_positive_integer!(@animation[:framerate], "animation.framerate")
      validate_positive_number!(@animation[:playback_speed], "animation.playback_speed")
    end

    def validate_cursor!
      return if self.class::VALID_CURSOR_STYLES.include?(@cursor[:style])

      raise ValidationError, "cursor.style must be one of: #{self.class::VALID_CURSOR_STYLES.join(", ")}"
    end

    def validate_lines!
      raise ValidationError, "lines must be an Array" unless @lines.is_a?(Array)
      raise ValidationError, "frames must be an Array" unless @frames.is_a?(Array)
    end

    def validate_limits!
      @limits.each_key do |key|
        validate_positive_integer!(@limits[key], "limits.#{key}")
      end
    end

    def validate_headless!
      validate_boolean!(@headless, "headless")
    end

    def validate_resource_limits!
      raise ResourceLimitError, "Too many lines (max #{@limits[:max_lines]})" if @lines.size > @limits[:max_lines]
      raise ResourceLimitError, "Too many frames (max #{@limits[:max_frames]})" if @frames.size > @limits[:max_frames]

      total_characters = (@lines.sum { |line| line.to_s.length } + @frames.sum { |frame| frame.to_s.length })
      return if total_characters <= @limits[:max_characters]

      raise ResourceLimitError, "Configuration text is too large (max #{@limits[:max_characters]} characters)"
    end

    def validate_overflow!
      return if self.class::VALID_OVERFLOW_MODES.include?(@window[:overflow])

      raise ValidationError, "window.overflow must be one of: #{self.class::VALID_OVERFLOW_MODES.join(", ")}"
    end

    def validate_ansi_state!
      return if %w[persistent line].include?(@window[:ansi_state])

      raise ValidationError, "window.ansi_state must be persistent or line"
    end

    def validate_background_gradient!
      gradient = @window[:background_gradient]
      return if gradient.nil?
      return if gradient.is_a?(Array) && gradient.size == 2 && gradient.all? { |color| color.is_a?(String) }

      raise ValidationError, "window.background_gradient must be an array of two colors"
    end

    def validate_minimum_width!
      min_width = [120, (@window[:padding] * 2) + 40].max
      return if @window[:width] >= min_width

      raise ValidationError, "window.width must be at least #{min_width}px for the configured padding"
    end

    def validate_optional_positive_integer!(value, name)
      return if value.nil?

      validate_positive_integer!(value, name)
    end

    def validate_optional_non_negative_integer!(value, name)
      return if value.nil?

      validate_non_negative_integer!(value, name)
    end

    def validate_optional_string!(value, name)
      return if value.nil? || value.is_a?(String)

      raise ValidationError, "#{name} must be a string"
    end

    def validate_positive_integer!(value, name)
      return if value.is_a?(Integer) && value.positive?

      raise ValidationError, "#{name} must be a positive integer"
    end

    def validate_non_negative_integer!(value, name)
      return if value.is_a?(Integer) && value >= 0

      raise ValidationError, "#{name} must be a non-negative integer"
    end

    def validate_positive_number!(value, name)
      return if value.is_a?(Numeric) && value.positive?

      raise ValidationError, "#{name} must be a positive number"
    end

    def validate_number_range!(value, name, min, max)
      return if value.is_a?(Numeric) && value >= min && value <= max

      raise ValidationError, "#{name} must be between #{min} and #{max}"
    end

    def validate_inclusion!(value, name, allowed)
      return if allowed.include?(value)

      raise ValidationError, "#{name} must be one of: #{allowed.join(", ")}"
    end

    def validate_boolean!(value, name)
      return if value == true || value == false

      raise ValidationError, "#{name} must be true or false"
    end
  end
end
