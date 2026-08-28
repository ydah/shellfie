# frozen_string_literal: true

module Shellfie
  module ConfigValidation
    RESOURCE_LIMIT_CEILINGS = {
      max_lines: 10_000,
      max_frames: 500,
      max_render_frames: 2_000,
      max_characters: 200_000,
      max_pixels: 50_000_000,
      max_total_pixels: 2_000_000_000,
      max_temp_bytes: 8_000_000_000
    }.freeze
    MAX_FRAME_DELAY_MS = 86_400_000

    def validate!
      validate_version!
      validate_theme!
      validate_window!
      validate_appearance!
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
      raise ValidationError, "window.padding must be at most 40" if @window[:padding] > 40
      %i[opacity scroll_offset].each { |key| validate_number_range!(@window[key], "window.#{key}", 0.0, 1.0) }
      validate_optional_positive_integer!(@window[:visible_lines], "window.visible_lines")
      validate_optional_positive_integer!(@window[:max_lines], "window.max_lines")
      validate_optional_positive_integer!(@window[:max_height], "window.max_height")
      validate_optional_non_negative_integer!(@window[:margin], "window.margin")
      validate_positive_integer!(@window[:tab_width], "window.tab_width")
      validate_inclusion!(@window[:ambiguous_width], "window.ambiguous_width", [1, 2])
      validate_inclusion!(@window[:osc_policy], "window.osc_policy", %w[ignore preserve apply])
      validate_boolean!(@window[:wrap], "window.wrap")
      validate_boolean!(@window[:exact_size], "window.exact_size")
      validate_boolean!(@window[:trim], "window.trim")
      validate_overflow!
      validate_ansi_state!
      validate_background_gradient!
      validate_minimum_width!
    end

    def validate_appearance!
      raise ValidationError, "title must be a string" unless @title.is_a?(String)
      unless @colors.values.all?(String)
        raise ValidationError, "colors values must be strings"
      end
      %i[title_bar_height button_size button_spacing button_width corner_radius].each do |key|
        next unless @window_decoration.key?(key)

        validate_non_negative_number!(@window_decoration[key], "window_decoration.#{key}")
      end
      return unless @window_decoration.key?(:shadow)

      shadow = @window_decoration[:shadow]
      raise ValidationError, "window_decoration.shadow must be a mapping" unless shadow.is_a?(Hash)
      validate_non_negative_number!(shadow[:blur], "window_decoration.shadow.blur") if shadow.key?(:blur)
      %i[offset_x offset_y].each do |key|
        validate_finite_number!(shadow[key], "window_decoration.shadow.#{key}") if shadow.key?(key)
      end
      if shadow.key?(:color) && !shadow[:color].is_a?(String)
        raise ValidationError, "window_decoration.shadow.color must be a string"
      end
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
      validate_non_negative_integer!(@animation[:seed], "animation.seed")
      raise ValidationError, "animation.seed must be at most 2147483647" if @animation[:seed] > 2_147_483_647
      validate_positive_integer!(@animation[:typing_chunk_size], "animation.typing_chunk_size")
      validate_non_negative_integer!(@animation[:output_delay], "animation.output_delay")
      validate_non_negative_integer!(@animation[:final_delay], "animation.final_delay")
      %i[typing_speed command_delay output_delay final_delay].each do |key|
        if @animation[key] > MAX_FRAME_DELAY_MS
          raise ValidationError, "animation.#{key} must be at most #{MAX_FRAME_DELAY_MS}"
        end
      end
      validate_optional_positive_integer!(@animation[:max_frames], "animation.max_frames")
      validate_boolean!(@animation[:cursor_blink], "animation.cursor_blink")
      validate_boolean!(@animation[:loop], "animation.loop")
      validate_boolean!(@animation[:dither], "animation.dither")
      validate_boolean!(@animation[:gif_optimize], "animation.gif_optimize")
      validate_boolean!(@animation[:webp_lossless], "animation.webp_lossless")
      validate_inclusion!(@animation[:palette], "animation.palette", self.class::VALID_PALETTES)
      validate_inclusion!(@animation[:apng_prediction], "animation.apng_prediction", self.class::VALID_APNG_PREDICTIONS)
      validate_positive_integer!(@animation[:gif_colors], "animation.gif_colors")
      raise ValidationError, "animation.gif_colors must be between 2 and 256" unless @animation[:gif_colors].between?(2, 256)
      %i[webp_quality webp_near_lossless].each do |key|
        validate_non_negative_integer!(@animation[key], "animation.#{key}")
        raise ValidationError, "animation.#{key} must be at most 100" if @animation[key] > 100
      end
      validate_non_negative_integer!(@animation[:webp_method], "animation.webp_method")
      raise ValidationError, "animation.webp_method must be at most 6" if @animation[:webp_method] > 6
      unless @animation[:loop_count].nil?
        validate_non_negative_integer!(@animation[:loop_count], "animation.loop_count")
        raise ValidationError, "animation.loop_count must be at most 65535" if @animation[:loop_count] > 65_535
      end
      validate_inclusion!(@animation[:scroll_easing], "animation.scroll_easing", self.class::VALID_SCROLL_EASINGS)
      validate_positive_integer!(@animation[:framerate], "animation.framerate")
      validate_positive_number!(@animation[:playback_speed], "animation.playback_speed")
      raise ValidationError, "animation.framerate must be at most 120" if @animation[:framerate] > 120
      raise ValidationError, "animation.playback_speed must be at most 100" if @animation[:playback_speed] > 100
    end

    def validate_cursor!
      return if self.class::VALID_CURSOR_STYLES.include?(@cursor[:style])

      raise ValidationError, "cursor.style must be one of: #{self.class::VALID_CURSOR_STYLES.join(", ")}"
    end

    def validate_lines!
      raise ValidationError, "lines must be an Array" unless @lines.is_a?(Array)
      raise ValidationError, "frames must be an Array" unless @frames.is_a?(Array)
      @frames.each_with_index do |frame, index|
        unless frame.respond_to?(:delay) && frame.delay.is_a?(Integer) && frame.delay.between?(0, MAX_FRAME_DELAY_MS)
          raise ValidationError, "frames[#{index}].delay must be between 0 and #{MAX_FRAME_DELAY_MS}"
        end
      end
    end

    def validate_limits!
      unknown = @limits.keys - RESOURCE_LIMIT_CEILINGS.keys
      raise ValidationError, "Unknown limits key(s): #{unknown.join(", ")}" unless unknown.empty?

      @limits.each_key do |key|
        validate_positive_integer!(@limits[key], "limits.#{key}")
        ceiling = RESOURCE_LIMIT_CEILINGS.fetch(key)
        raise ValidationError, "limits.#{key} must be at most #{ceiling}" if @limits[key] > ceiling
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
      return if @window[:width] >= 120

      raise ValidationError, "window.width must be at least 120px"
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
      return if value.is_a?(Numeric) && value.finite? && value.positive?

      raise ValidationError, "#{name} must be a positive number"
    end

    def validate_non_negative_number!(value, name)
      return if value.is_a?(Numeric) && value.finite? && value >= 0

      raise ValidationError, "#{name} must be a non-negative number"
    end

    def validate_finite_number!(value, name)
      return if value.is_a?(Numeric) && value.finite?

      raise ValidationError, "#{name} must be a finite number"
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
