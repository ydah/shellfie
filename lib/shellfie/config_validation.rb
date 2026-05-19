# frozen_string_literal: true

module Shellfie
  module ConfigValidation
    def validate!
      validate_theme!
      validate_window!
      validate_font!
      validate_animation!
      validate_cursor!
      validate_lines!
    end

    private

    def validate_theme!
      return if self.class::VALID_THEMES.include?(@theme)

      raise ValidationError, "Invalid theme '#{@theme}'\n  → Available themes: #{self.class::VALID_THEMES.join(", ")}"
    end

    def validate_window!
      validate_positive_integer!(@window[:width], "window.width")
      validate_non_negative_integer!(@window[:padding], "window.padding")
      validate_number_range!(@window[:opacity], "window.opacity", 0.0, 1.0)
      validate_optional_positive_integer!(@window[:visible_lines], "window.visible_lines")
      validate_optional_positive_integer!(@window[:max_lines], "window.max_lines")
      validate_optional_positive_integer!(@window[:max_height], "window.max_height")
      validate_optional_non_negative_integer!(@window[:margin], "window.margin")
      validate_positive_integer!(@window[:tab_width], "window.tab_width")
      validate_overflow!
      validate_ansi_state!
      validate_minimum_width!
    end

    def validate_font!
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
    end

    def validate_cursor!
      return if self.class::VALID_CURSOR_STYLES.include?(@cursor[:style])

      raise ValidationError, "cursor.style must be one of: #{self.class::VALID_CURSOR_STYLES.join(", ")}"
    end

    def validate_lines!
      raise ValidationError, "lines must be an Array" unless @lines.is_a?(Array)
      raise ValidationError, "frames must be an Array" unless @frames.is_a?(Array)
    end

    def validate_overflow!
      return if self.class::VALID_OVERFLOW_MODES.include?(@window[:overflow])

      raise ValidationError, "window.overflow must be one of: #{self.class::VALID_OVERFLOW_MODES.join(", ")}"
    end

    def validate_ansi_state!
      return if %w[persistent line].include?(@window[:ansi_state])

      raise ValidationError, "window.ansi_state must be persistent or line"
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
  end
end
