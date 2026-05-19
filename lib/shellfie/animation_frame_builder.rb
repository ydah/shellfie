# frozen_string_literal: true

module Shellfie
  class AnimationFrameBuilder
    def initialize(config)
      @config = config
      @random = Random.new(0)
    end

    def build
      return [{ lines: @config.lines, delay: @config.animation[:final_delay] }] if @config.frames.empty?

      frames = []
      current_lines = []
      @config.frames.each do |frame|
        frames.concat(command_frames(current_lines, frame)) if frame.type
        frames.concat(output_frames(current_lines, frame)) if frame.output
        if frame.delay&.positive? && !frame.output && !frame.type
          frames << { lines: build_display_lines(current_lines), delay: frame.delay }
        end
      end

      if @config.animation[:final_delay].positive?
        frames << { lines: build_display_lines(current_lines), delay: @config.animation[:final_delay] }
      end
      frames
    end

    def cursor_text
      glyph = case @config.cursor[:style]
              when "bar"
                "|"
              when "underline"
                "_"
              else
                "█"
              end
      color = @config.cursor[:color]
      return glyph unless color

      "#{ansi_color(color)}#{glyph}\e[0m"
    end

    private

    def command_frames(current_lines, frame)
      prompt = frame.prompt || ""
      frames = build_typing_frames(current_lines.dup, prompt, frame.type)
      current_lines << command_line(frame.prompt, frame.type)
      frames.concat(command_pause_frames(current_lines, prompt, frame.type))
      frames
    end

    def build_typing_frames(base_lines, prompt, command)
      frames = []
      chars = command.chars
      chunk_size = @config.animation[:typing_chunk_size]

      (chunk_size..chars.length).step(chunk_size).each do |index|
        typed = chars.first(index).join
        frames << typing_frame(base_lines, prompt, typed)
      end

      frames << typing_frame(base_lines, prompt, command) if chars.length % chunk_size != 0 || frames.empty?
      final_lines = base_lines.dup
      final_lines << command_line(prompt, command)
      frames << { lines: build_display_lines(final_lines), delay: @config.animation[:typing_speed] }
      frames
    end

    def typing_frame(base_lines, prompt, typed)
      lines = base_lines.dup
      lines << command_line(prompt, typed, cursor: true)
      {
        lines: build_display_lines(lines),
        delay: jittered_delay(@config.animation[:typing_speed], @config.animation[:typing_jitter])
      }
    end

    def command_pause_frames(current_lines, prompt, command)
      delay = @config.animation[:command_delay]
      return [] unless delay.positive?
      return [{ lines: build_display_lines(current_lines), delay: delay }] unless @config.animation[:cursor_blink]

      half_delay = [delay / 2, 1].max
      [
        { lines: build_display_lines(current_lines[0...-1] + [command_line(prompt, command, cursor: true)]), delay: half_delay },
        { lines: build_display_lines(current_lines), delay: delay - half_delay }
      ]
    end

    def output_frames(current_lines, frame)
      output_lines = frame.output.to_s.split("\n", -1)
      output_delay = @config.animation[:output_delay]

      if output_delay.positive?
        output_lines.map do |line|
          current_lines << { output: line, output_color: frame.output_color }
          { lines: build_display_lines(current_lines), delay: output_delay }
        end
      else
        output_lines.each { |line| current_lines << { output: line, output_color: frame.output_color } }
        [{ lines: build_display_lines(current_lines), delay: frame.delay || 100 }]
      end
    end

    def command_line(prompt, command, cursor: false)
      { prompt: prompt, command: command, cursor: cursor }
    end

    def build_display_lines(lines_data)
      lines_data.map do |line_data|
        if line_data[:prompt]
          text = "#{line_data[:prompt]}#{line_data[:command]}"
          text += cursor_text if line_data[:cursor]
          Line.new(prompt: text, command: nil, output: nil)
        else
          Line.new(prompt: nil, command: nil, output: line_data[:output], output_color: line_data[:output_color])
        end
      end
    end

    def ansi_color(color)
      return "" unless color.to_s.match?(/\A#[0-9a-fA-F]{6}\z/)

      r = color[1, 2].to_i(16)
      g = color[3, 2].to_i(16)
      b = color[5, 2].to_i(16)
      "\e[38;2;#{r};#{g};#{b}m"
    end

    def jittered_delay(base_delay, jitter)
      return base_delay unless jitter.positive?

      factor = 1.0 + @random.rand(-jitter..jitter)
      [(base_delay * factor).round, 1].max
    end
  end
end
