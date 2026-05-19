# frozen_string_literal: true

require "mini_magick"
require "tmpdir"
require_relative "animation_frame_builder"
require_relative "renderer"

module Shellfie
  class GifGenerator
    attr_reader :config, :theme

    def initialize(config)
      @config = config
      @renderer = Renderer.new(config)
      @theme = @renderer.theme
      @frame_builder = AnimationFrameBuilder.new(config)
    end

    def generate(output_path, scale: 1, shadow: true, transparent: false)
      check_dependencies!

      images = []
      begin
        frames = build_animation_frames
        warn_frame_count(frames)
        images = render_frames(frames, scale: scale, shadow: shadow, transparent: transparent)
        combine_to_gif(images, output_path)
      ensure
        cleanup_temp_files(images)
      end
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
      @frame_builder.build
    end

    def cursor_text
      @frame_builder.cursor_text
    end

    def render_frames(frames, scale:, shadow:, transparent:)
      temp_dir = Dir.mktmpdir("shellfie")
      images = []

      frames.each_with_index do |frame, idx|
        frame_config = create_frame_config(frame[:lines])
        renderer = Renderer.new(frame_config)
        output_path = File.join(temp_dir, "frame_#{format("%04d", idx)}.png")
        renderer.render(output_path, scale: scale, shadow: shadow, transparent: transparent)
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
        animation: config.animation,
        cursor: config.cursor,
        headless: config.headless
      )
    end

    def combine_to_gif(images, output_path)
      MiniMagick.convert do |convert|
        convert.dispose "none"
        convert.loop config.animation[:loop] ? 0 : 1

        images.each do |img|
          convert.delay gif_delay(img[:delay])
          convert << img[:path]
        end

        convert.dither "FloydSteinberg" if config.animation[:dither]
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

    def gif_delay(milliseconds)
      [(milliseconds / 10.0).round, 1].max
    end

    def warn_frame_count(frames)
      max_frames = config.animation[:max_frames]
      return unless max_frames && frames.size > max_frames

      $stderr.puts "Warning: animation will generate #{frames.size} frames (max_frames is #{max_frames})"
    end
  end
end
