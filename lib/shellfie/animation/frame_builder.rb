# frozen_string_literal: true

require_relative 'scroll_easing'
require_relative 'timeline'
require_relative '../terminal/text_metrics'

module Shellfie
  class AnimationFrameBuilder
    def initialize(config)
      @config = config
      @random = Random.new(config.animation[:seed])
      @scroll_easing = AnimationScrollEasing.new(config)
    end

    def build
      return [{ lines: @config.lines, delay: @config.animation[:final_delay] }] if @config.frames.empty?

      frames = []
      current_lines = @config.lines.flat_map { |line| line_data(line) }
      AnimationTimeline.new(@config).each do |event|
        case event.kind
        when :screen
          current_lines.replace(event.frame.screen.map { |line| { output: line } })
          frames << { lines: build_display_lines(current_lines), delay: [event.frame.delay, 1].max }
        when :command
          frames.concat(command_frames(current_lines, event.frame))
        when :output
          frames.concat(output_frames(current_lines, event.frame))
        when :pause
          frames << { lines: build_display_lines(current_lines), delay: event.frame.delay }
        end
      end

      if @config.animation[:final_delay].positive?
        frames << { lines: build_display_lines(current_lines), delay: @config.animation[:final_delay] }
      end
      frames
    end

    def cursor_text
      glyph = case @config.cursor[:style]
              when 'bar'
                '|'
              when 'underline'
                '_'
              else
                '█'
              end
      color = @config.cursor[:color]
      return glyph unless color

      "#{ansi_color(color)}#{glyph}\e[0m"
    end

    private

    def command_frames(current_lines, frame)
      prompt = frame.prompt || ''
      frames = build_typing_frames(current_lines.dup, frame)
      current_lines << command_line(prompt, frame.type, prompt_color: frame.prompt_color,
                                                        command_color: frame.command_color)
      frames.concat(command_pause_frames(current_lines, frame))
      frames
    end

    def build_typing_frames(base_lines, frame)
      frames = []
      prompt = frame.prompt || ''
      command = frame.type
      chars = TextMetrics.graphemes(command)
      chunk_size = @config.animation[:typing_chunk_size]

      (chunk_size..chars.length).step(chunk_size).each do |index|
        typed = chars.first(index).join
        frames << typing_frame(base_lines, frame, typed)
      end

      frames << typing_frame(base_lines, frame, command) if chars.length % chunk_size != 0 || frames.empty?
      final_lines = base_lines.dup
      final_lines << command_line(prompt, command, prompt_color: frame.prompt_color, command_color: frame.command_color)
      frames << { lines: build_display_lines(final_lines), delay: @config.animation[:typing_speed] }
      frames
    end

    def typing_frame(base_lines, frame, typed)
      lines = base_lines.dup
      lines << command_line(
        frame.prompt || '',
        typed,
        cursor: true,
        prompt_color: frame.prompt_color,
        command_color: frame.command_color
      )
      {
        lines: build_display_lines(lines),
        delay: jittered_delay(@config.animation[:typing_speed], @config.animation[:typing_jitter])
      }
    end

    def command_pause_frames(current_lines, frame)
      delay = if frame.output
                @config.animation[:command_delay]
              else
                frame.delay.positive? ? frame.delay : @config.animation[:command_delay]
              end
      return [] unless delay.positive?
      return [{ lines: build_display_lines(current_lines), delay: delay }] unless @config.animation[:cursor_blink]

      half_delay = [delay / 2, 1].max
      [
        { lines: build_display_lines(current_lines[0...-1] + [cursor_command_line(frame)]), delay: half_delay },
        { lines: build_display_lines(current_lines), delay: delay - half_delay }
      ]
    end

    def output_frames(current_lines, frame)
      output_lines = frame.output.to_s.split("\n", -1)
      output_delay = @config.animation[:output_delay]

      if output_delay.positive?
        frames = output_lines.each_with_index.with_object([]) do |(line, index), result|
          previous_count = current_lines.size
          current_lines << { output: line, output_color: frame.output_color }
          delay = @scroll_easing.output_delay(output_delay, index, output_lines.size)
          result.concat(
            @scroll_easing.transition_frames(
              build_display_lines(current_lines),
              delay: delay,
              previous_count: previous_count
            )
          )
        end
        frames << { lines: build_display_lines(current_lines), delay: frame.delay } if frame.delay.positive?
        frames
      else
        output_lines.each { |line| current_lines << { output: line, output_color: frame.output_color } }
        [{ lines: build_display_lines(current_lines), delay: [frame.delay, 1].max }]
      end
    end

    def command_line(prompt, command, cursor: false, prompt_color: nil, command_color: nil)
      { prompt: prompt, command: command, cursor: cursor, prompt_color: prompt_color, command_color: command_color }
    end

    def line_data(line)
      data = []
      if line.prompt || line.command
        data << command_line(
          line.prompt,
          line.command,
          prompt_color: line.prompt_color,
          command_color: line.command_color
        )
      end
      if line.output
        data.concat(line.output.to_s.split("\n", -1).map do |output|
          { output: output, output_color: line.output_color }
        end)
      end
      data
    end

    def cursor_command_line(frame)
      command_line(
        frame.prompt || '',
        frame.type,
        cursor: true,
        prompt_color: frame.prompt_color,
        command_color: frame.command_color
      )
    end

    def build_display_lines(lines_data)
      lines_data.map do |line_data|
        if line_data[:prompt]
          command = line_data[:command].to_s
          command += cursor_text if line_data[:cursor]
          Line.new(
            prompt: line_data[:prompt],
            command: command,
            output: nil,
            prompt_color: line_data[:prompt_color],
            command_color: line_data[:command_color]
          )
        else
          Line.new(prompt: nil, command: nil, output: line_data[:output], output_color: line_data[:output_color])
        end
      end
    end

    def ansi_color(color)
      return '' unless color.to_s.match?(/\A#[0-9a-fA-F]{6}\z/)

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
