# frozen_string_literal: true

require "mini_magick"
require_relative "renderer"

module Shellfie
  class GifGenerator
    attr_reader :config, :theme

    def initialize(config)
      @config = config
      @renderer = Renderer.new(config)
      @theme = @renderer.theme
    end

    def generate(output_path, scale: 1, shadow: true)
      check_dependencies!

      frames = build_animation_frames
      images = render_frames(frames, scale: scale, shadow: shadow)
      combine_to_gif(images, output_path)
      cleanup_temp_files(images)
      output_path
    end

    private

    def check_dependencies!
      result = `which magick 2>/dev/null || which convert 2>/dev/null`.strip
      if result.empty?
        raise DependencyError, <<~MSG
          ImageMagick not found
            → Please install ImageMagick: brew install imagemagick
            → Or visit: https://imagemagick.org/script/download.php
        MSG
      end
    end

    def build_animation_frames
      frames = []
      current_lines = []
      animation_settings = config.animation

      config.frames.each do |frame|
        if frame.type
          typing_frames = build_typing_frames(
            current_lines.dup,
            frame.prompt || "",
            frame.type,
            animation_settings[:typing_speed] || 80
          )
          frames.concat(typing_frames)
          current_lines << { prompt: frame.prompt, command: frame.type }
        end

        if frame.output
          frame.output.split("\n").each do |line|
            current_lines << { output: line }
          end
          frames << { lines: build_display_lines(current_lines), delay: frame.delay || 100 }
        end

        if frame.delay && frame.delay > 0 && !frame.output
          frames << { lines: build_display_lines(current_lines), delay: frame.delay }
        end
      end

      frames
    end

    def build_typing_frames(base_lines, prompt, command, typing_speed)
      frames = []
      chars = command.chars

      chars.each_with_index do |_char, i|
        typed = command[0..i]
        lines = base_lines.dup
        lines << { prompt: prompt, command: typed, cursor: true }
        frames << { lines: build_display_lines(lines), delay: typing_speed }
      end

      final_lines = base_lines.dup
      final_lines << { prompt: prompt, command: command }
      frames << { lines: build_display_lines(final_lines), delay: typing_speed }

      frames
    end

    def build_display_lines(lines_data)
      lines_data.map do |line_data|
        if line_data[:prompt]
          text = "#{line_data[:prompt]}#{line_data[:command]}"
          text += "█" if line_data[:cursor]
          Line.new(prompt: text, command: nil, output: nil)
        else
          Line.new(prompt: nil, command: nil, output: line_data[:output])
        end
      end
    end

    def render_frames(frames, scale:, shadow:)
      temp_dir = Dir.mktmpdir("shellfie")
      images = []

      frames.each_with_index do |frame, idx|
        frame_config = create_frame_config(frame[:lines])
        renderer = Renderer.new(frame_config)
        output_path = File.join(temp_dir, "frame_#{format("%04d", idx)}.png")
        renderer.render(output_path, scale: scale, shadow: shadow)
        images << { path: output_path, delay: frame[:delay] }
      end

      images
    end

    def create_frame_config(lines)
      Config.new(
        theme: config.theme,
        title: config.title,
        window: config.window,
        font: config.font,
        lines: lines,
        headless: config.headless
      )
    end

    def combine_to_gif(images, output_path)
      MiniMagick.convert do |convert|
        convert.dispose "none"
        convert.loop config.animation[:loop] ? 0 : 1

        images.each do |img|
          delay = (img[:delay] / 10.0).round
          convert.delay delay
          convert << img[:path]
        end

        convert.dither "FloydSteinberg"
        convert.colors 256
        convert.layers "optimize"
        convert << output_path
      end
    end

    def cleanup_temp_files(images)
      images.each { |img| File.delete(img[:path]) if File.exist?(img[:path]) }
      temp_dir = File.dirname(images.first[:path]) if images.any?
      Dir.rmdir(temp_dir) if temp_dir && Dir.exist?(temp_dir) && Dir.empty?(temp_dir)
    end
  end
end
