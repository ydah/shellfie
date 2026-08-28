# frozen_string_literal: true

require "mini_magick"
require "fileutils"
require "tmpdir"
require_relative "animation_frame_builder"
require_relative "dependency_checker"
require_relative "format_resolver"
require_relative "ffmpeg_encoder"
require_relative "gif_palette"
require_relative "image_magick_command_builder"
require_relative "output_writer"
require_relative "render_chrome_cache"
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

    def generate(output_path, scale: 1, shadow: true, transparent: false, format: nil, io: nil)
      check_dependencies!

      images = []
      chrome_cache = RenderChromeCache.new
      begin
        frames = coalesce_frames(build_animation_frames)
        validate_frame_limit!(frames)
        validate_workload!(frames, scale: scale, shadow: shadow)
        warn_frame_count(frames)
        images = render_frames(frames, scale: scale, shadow: shadow, transparent: transparent, chrome_cache: chrome_cache)
        extension = FormatResolver.resolve(output_path, explicit: format, default: "gif")
        OutputWriter.write(output_path, extension: extension, io: io) do |temporary_path|
          combine_to_animation(images, temporary_path, format: extension)
        end
      ensure
        cleanup_temp_files(images)
        chrome_cache.cleanup
      end
    rescue MiniMagick::Error => e
      raise RenderError.new("ImageMagick animation render failed: #{e.message}", category: :render)
    end

    private

    def check_dependencies!
      DependencyChecker.configure_mini_magick!
      DependencyChecker.ensure_imagemagick!
    end

    def build_animation_frames
      @frame_builder.build
    end

    def cursor_text
      @frame_builder.cursor_text
    end

    def render_frames(frames, scale:, shadow:, transparent:, chrome_cache:)
      temp_dir = Dir.mktmpdir("shellfie")
      images = []

      frames.each_with_index do |frame, idx|
        frame_config = create_frame_config(frame[:lines], window_overrides: frame[:window] || {})
        renderer = Renderer.new(frame_config, chrome_cache: chrome_cache)
        output_path = File.join(temp_dir, "frame_#{format("%04d", idx)}.png")
        renderer.render(output_path, scale: scale, shadow: shadow, transparent: transparent)
        images << { path: output_path, delay: frame[:delay] }
      end

      images
    end

    def create_frame_config(lines, window_overrides: {})
      Config.new(
        theme: config.theme,
        window_theme: config.window_theme,
        color_scheme: config.color_scheme,
        colors: config.colors,
        window_decoration: config.window_decoration,
        title: config.title,
        window: config.window.merge(window_overrides),
        font: config.font,
        lines: lines,
        animation: config.animation,
        cursor: config.cursor,
        limits: config.limits,
        headless: config.headless
      )
    end

    def combine_to_animation(images, output_path, format:)
      if %w[mp4 webm].include?(format)
        DependencyChecker.ensure_ffmpeg!
        return FfmpegEncoder.encode(images, output_path, format: format, command: DependencyChecker.ffmpeg_path)
      end

      palette = GifPalette.new(config: config, theme: theme) if format == "gif"
      ImageMagickCommandBuilder.convert do |convert|
        convert.dispose "none" if format == "gif"
        convert.loop config.animation[:loop] ? 0 : 1

        images.each do |img|
          convert.delay gif_delay(img[:delay])
          convert << img[:path]
        end

        configure_animation_format(convert, format, images: images, palette: palette)
        ImageMagickCommandBuilder.output(convert, output_path, format: format)
      end
    ensure
      palette&.cleanup
    end

    def configure_animation_format(convert, format, images:, palette:)
      case format
      when "gif"
        palette.apply(convert, images: images)
        convert.layers "optimize"
      when "webp"
        convert.define "webp:lossless=true"
      end
    end

    def cleanup_temp_files(images)
      temp_dir = File.dirname(images.first[:path]) if images.any?
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end

    def gif_delay(milliseconds)
      frame_ms = 1_000.0 / config.animation[:framerate]
      adjusted = milliseconds / config.animation[:playback_speed]
      quantized = [(adjusted / frame_ms).round * frame_ms, frame_ms].max
      [(quantized / 10.0).round, 1].max
    end

    def warn_frame_count(frames)
      max_frames = config.animation[:max_frames]
      return unless max_frames && frames.size > max_frames

      $stderr.puts "Warning: animation will generate #{frames.size} frames (max_frames is #{max_frames})"
    end

    def validate_frame_limit!(frames)
      return if frames.size <= config.limits[:max_render_frames]

      raise ResourceLimitError, "Animation would generate #{frames.size} frames (max #{config.limits[:max_render_frames]})"
    end

    def coalesce_frames(frames)
      frames.each_with_object([]) do |frame, result|
        if result.last && frame_key(result.last) == frame_key(frame)
          result.last[:delay] += frame[:delay]
        else
          result << frame.merge(lines: frame[:lines].dup)
        end
      end
    end

    def frame_key(frame)
      [frame[:lines].map(&:to_h), frame[:window]]
    end

    def validate_workload!(frames, scale:, shadow:)
      geometry = @renderer.estimate(scale: scale, shadow: shadow)
      total_pixels = geometry[:canvas_width] * geometry[:canvas_height] * frames.size
      if total_pixels > config.limits[:max_total_pixels]
        raise ResourceLimitError,
              "Animation workload is too large (#{total_pixels} pixels, max #{config.limits[:max_total_pixels]})"
      end

      estimated_bytes = total_pixels * 4
      return if estimated_bytes <= config.limits[:max_temp_bytes]

      raise ResourceLimitError,
            "Animation temporary data is too large (#{estimated_bytes} bytes, max #{config.limits[:max_temp_bytes]})"
    end

  end
end
