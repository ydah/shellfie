# frozen_string_literal: true

require "did_you_mean"

module Shellfie
  module ParserValidation
    MAX_FRAME_DELAY_MS = 86_400_000
    TOP_LEVEL_KEYS = %i[
      version include include_policy theme window_theme color_scheme colors window_decoration title window font animation cursor lines frames
      headless limits
    ].freeze
    WINDOW_KEYS = %i[
      width padding opacity visible_lines max_lines max_height wrap overflow margin exact_size trim tab_width
      ambiguous_width osc_policy ansi_state background_gradient scroll_offset
    ].freeze
    FONT_KEYS = %i[family size line_height fallback_family italic_family emoji_family].freeze
    ANIMATION_KEYS = %i[
      typing_speed command_delay cursor_blink loop typing_jitter seed typing_chunk_size output_delay final_delay max_frames
      dither palette gif_colors gif_optimize webp_lossless webp_quality webp_method webp_near_lossless
      apng_prediction loop_count scroll_easing
      direction loop_offset
      framerate playback_speed
    ].freeze
    CURSOR_KEYS = %i[style color].freeze
    LIMIT_KEYS = %i[max_lines max_frames max_render_frames max_characters max_pixels max_total_pixels max_temp_bytes].freeze
    LINE_KEYS = %i[prompt command output prompt_color command_color output_color selected].freeze
    FRAME_KEYS = %i[prompt type output screen delay prompt_color command_color output_color].freeze
    COLOR_KEYS = %i[
      background foreground title_bar title_text title_bar_border border selection black red green yellow blue magenta cyan
      white bright_black bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan bright_white
    ].freeze
    WINDOW_DECORATION_KEYS = %i[
      title_bar_height button_size button_spacing button_width corner_radius shadow
    ].freeze
    SHADOW_KEYS = %i[blur offset_x offset_y color].freeze

    private

    def validate_config(raw)
      raise ValidationError, "Empty configuration" if raw.nil? || (raw.respond_to?(:empty?) && raw.empty?)
      raise ValidationError, "Configuration must be a YAML mapping" unless raw.is_a?(Hash)

      validate_keys!(raw, TOP_LEVEL_KEYS, "configuration")
      validate_nested_hash!(raw, :window, WINDOW_KEYS)
      validate_nested_hash!(raw, :font, FONT_KEYS)
      validate_nested_hash!(raw, :animation, ANIMATION_KEYS)
      validate_nested_hash!(raw, :cursor, CURSOR_KEYS)
      validate_nested_hash!(raw, :limits, LIMIT_KEYS)
      validate_nested_hash!(raw, :colors, COLOR_KEYS)
      validate_nested_hash!(raw, :window_decoration, WINDOW_DECORATION_KEYS)
      if raw.dig(:window_decoration, :shadow)
        validate_nested_hash!(raw[:window_decoration], :shadow, SHADOW_KEYS, "window_decoration.shadow")
      end
      validate_theme!(raw[:theme]) if raw[:theme]
      validate_window_theme!(raw[:window_theme]) if raw[:window_theme]
      validate_color_scheme!(raw[:color_scheme]) if raw.key?(:color_scheme)
      if raw[:include_policy] && !%w[allow root].include?(raw[:include_policy])
        raise ValidationError, "include_policy must be allow or root"
      end

      raise ValidationError, "Configuration must have either 'lines' or 'frames'" if raw[:lines].nil? && raw[:frames].nil?

      validate_lines!(raw[:lines]) if raw.key?(:lines)
      validate_frames!(raw[:frames]) if raw.key?(:frames)
    end

    def validate_theme!(theme)
      return if ThemeRegistry.valid_theme?(theme)

      raise ValidationError, "Invalid theme '#{theme}'\n  → Available themes: #{ThemeRegistry.available_themes.join(", ")}"
    end

    def validate_window_theme!(theme)
      return if ThemeRegistry.valid_window_theme?(theme)

      raise ValidationError, "Invalid window_theme '#{theme}'"
    end

    def validate_color_scheme!(scheme)
      return if ThemeRegistry.valid_color_scheme?(scheme)

      raise ValidationError, "Invalid color_scheme '#{scheme}'"
    end

    def validate_nested_hash!(raw, key, allowed_keys, context = key.to_s)
      return unless raw.key?(key)
      raise ValidationError, "#{key} must be a mapping" unless raw[key].is_a?(Hash)

      validate_keys!(raw[key], allowed_keys, context) if allowed_keys
    end

    def validate_keys!(hash, allowed_keys, context)
      unknown_keys = hash.keys - allowed_keys
      return if unknown_keys.empty?

      suggestions = unknown_keys.filter_map do |key|
        match = DidYouMean::SpellChecker.new(dictionary: allowed_keys.map(&:to_s)).correct(key.to_s).first
        "#{key} -> #{match}" if match
      end
      hint = suggestions.empty? ? "" : " (did you mean #{suggestions.join(", ")}?)"
      raise ValidationError, "Unknown #{context} key(s): #{unknown_keys.join(", ")}#{hint}"
    end

    def validate_lines!(lines)
      raise ValidationError, "lines must be an array" unless lines.is_a?(Array)

      lines.each_with_index do |line, index|
        raise ValidationError, "lines[#{index}] must be a mapping" unless line.is_a?(Hash)

        validate_keys!(line, LINE_KEYS, "lines[#{index}]")
        if line.values_at(:prompt, :command, :output).all?(&:nil?)
          raise ValidationError, "lines[#{index}] must include at least one of prompt, command, or output"
        end
        validate_line_values!(line, index)
      end
    end

    def validate_frames!(frames)
      raise ValidationError, "frames must be an array" unless frames.is_a?(Array)

      frames.each_with_index do |frame, index|
        raise ValidationError, "frames[#{index}] must be a mapping" unless frame.is_a?(Hash)

        validate_keys!(frame, FRAME_KEYS, "frames[#{index}]")
        validate_frame_shape!(frame, index)
      end
    end

    def validate_line_values!(line, index)
      %i[prompt command output prompt_color command_color output_color].each do |key|
        validate_string_value!(line[key], "lines[#{index}].#{key}") if line.key?(key)
      end
      validate_boolean_value!(line[:selected], "lines[#{index}].selected") if line.key?(:selected)
    end

    def validate_frame_shape!(frame, index)
      raise ValidationError, "frames[#{index}].prompt requires type" if frame[:prompt] && frame[:type].nil?

      if frame.values_at(:type, :output, :screen, :delay).all?(&:nil?)
        raise ValidationError, "frames[#{index}] must include type, output, screen, or delay"
      end

      validate_string_value!(frame[:prompt], "frames[#{index}].prompt") if frame.key?(:prompt)
      validate_string_value!(frame[:type], "frames[#{index}].type") if frame.key?(:type)
      validate_string_value!(frame[:output], "frames[#{index}].output") if frame.key?(:output)
      if frame.key?(:screen) && (!frame[:screen].is_a?(Array) || !frame[:screen].all?(String))
        raise ValidationError, "frames[#{index}].screen must be an array of strings"
      end
      validate_string_value!(frame[:prompt_color], "frames[#{index}].prompt_color") if frame.key?(:prompt_color)
      validate_string_value!(frame[:command_color], "frames[#{index}].command_color") if frame.key?(:command_color)
      validate_string_value!(frame[:output_color], "frames[#{index}].output_color") if frame.key?(:output_color)
      if frame.key?(:delay)
        validate_non_negative_integer!(frame[:delay], "frames[#{index}].delay")
        if frame[:delay] > MAX_FRAME_DELAY_MS
          raise ValidationError, "frames[#{index}].delay must be at most #{MAX_FRAME_DELAY_MS}"
        end
      end
    end

    def validate_string_value!(value, name)
      return if value.is_a?(String)

      raise ValidationError, "#{name} must be a string"
    end

    def validate_boolean_value!(value, name)
      return if value == true || value == false

      raise ValidationError, "#{name} must be true or false"
    end

    def validate_non_negative_integer!(value, name)
      return if value.is_a?(Integer) && value >= 0

      raise ValidationError, "#{name} must be a non-negative integer"
    end
  end
end
