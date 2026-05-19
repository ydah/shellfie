# frozen_string_literal: true

module Shellfie
  module ParserValidation
    TOP_LEVEL_KEYS = %i[theme title window font animation cursor lines frames headless].freeze
    WINDOW_KEYS = %i[
      width padding opacity visible_lines max_lines max_height wrap overflow margin exact_size trim tab_width
      ansi_state background_gradient
    ].freeze
    FONT_KEYS = %i[family size line_height fallback_family italic_family emoji_family].freeze
    ANIMATION_KEYS = %i[
      typing_speed command_delay cursor_blink loop typing_jitter typing_chunk_size output_delay final_delay max_frames
      dither
    ].freeze
    CURSOR_KEYS = %i[style color].freeze
    LINE_KEYS = %i[prompt command output prompt_color command_color output_color selected].freeze
    FRAME_KEYS = %i[prompt type output delay prompt_color command_color output_color].freeze

    private

    def validate_config(raw)
      raise ValidationError, "Empty configuration" if raw.nil? || (raw.respond_to?(:empty?) && raw.empty?)
      raise ValidationError, "Configuration must be a YAML mapping" unless raw.is_a?(Hash)

      validate_keys!(raw, TOP_LEVEL_KEYS, "configuration")
      validate_nested_hash!(raw, :window, WINDOW_KEYS)
      validate_nested_hash!(raw, :font, FONT_KEYS)
      validate_nested_hash!(raw, :animation, ANIMATION_KEYS)
      validate_nested_hash!(raw, :cursor, CURSOR_KEYS)
      validate_theme!(raw[:theme]) if raw[:theme]

      raise ValidationError, "Configuration must have either 'lines' or 'frames'" if raw[:lines].nil? && raw[:frames].nil?

      validate_lines!(raw[:lines]) if raw.key?(:lines)
      validate_frames!(raw[:frames]) if raw.key?(:frames)
    end

    def validate_theme!(theme)
      return if Config::VALID_THEMES.include?(theme)

      raise ValidationError, "Invalid theme '#{theme}'\n  → Available themes: #{Config::VALID_THEMES.join(", ")}"
    end

    def validate_nested_hash!(raw, key, allowed_keys)
      return unless raw.key?(key)
      raise ValidationError, "#{key} must be a mapping" unless raw[key].is_a?(Hash)

      validate_keys!(raw[key], allowed_keys, key.to_s)
    end

    def validate_keys!(hash, allowed_keys, context)
      unknown_keys = hash.keys - allowed_keys
      return if unknown_keys.empty?

      raise ValidationError, "Unknown #{context} key(s): #{unknown_keys.join(", ")}"
    end

    def validate_lines!(lines)
      raise ValidationError, "lines must be an array" unless lines.is_a?(Array)

      lines.each_with_index do |line, index|
        raise ValidationError, "lines[#{index}] must be a mapping" unless line.is_a?(Hash)

        validate_keys!(line, LINE_KEYS, "lines[#{index}]")
        if line.values_at(:prompt, :command, :output).all?(&:nil?)
          raise ValidationError, "lines[#{index}] must include at least one of prompt, command, or output"
        end
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

    def validate_frame_shape!(frame, index)
      raise ValidationError, "frames[#{index}].prompt requires type" if frame[:prompt] && frame[:type].nil?

      if frame.values_at(:type, :output, :delay).all?(&:nil?)
        raise ValidationError, "frames[#{index}] must include type, output, or delay"
      end

      validate_string_value!(frame[:type], "frames[#{index}].type") if frame.key?(:type)
      validate_string_value!(frame[:output], "frames[#{index}].output") if frame.key?(:output)
      validate_non_negative_integer!(frame[:delay], "frames[#{index}].delay") if frame.key?(:delay)
    end

    def validate_string_value!(value, name)
      return if value.is_a?(String)

      raise ValidationError, "#{name} must be a string"
    end

    def validate_non_negative_integer!(value, name)
      return if value.is_a?(Integer) && value >= 0

      raise ValidationError, "#{name} must be a non-negative integer"
    end
  end
end
