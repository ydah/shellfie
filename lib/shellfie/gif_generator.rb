# frozen_string_literal: true

require "mini_magick"
require "fileutils"
require "json"
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
        frames = playback_frames(coalesce_frames(build_animation_frames))
        validate_frame_limit!(frames)
        validate_workload!(frames, scale: scale, shadow: shadow)
        warn_frame_count(frames)
        images = render_frames(frames, scale: scale, shadow: shadow, transparent: transparent, chrome_cache: chrome_cache)
        extension = FormatResolver.resolve(output_path, explicit: format, default: "gif")
        return write_png_sequence(images, output_path) if extension == "png-sequence"

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
      complete = false
      visible_lines = fixed_visible_lines(frames)

      frames.each_with_index do |frame, idx|
        frame_config = create_frame_config(
          frame[:lines],
          window_overrides: { visible_lines: visible_lines }.merge(frame[:window] || {})
        )
        renderer = Renderer.new(frame_config, chrome_cache: chrome_cache)
        output_path = File.join(temp_dir, "frame_#{format("%04d", idx)}.png")
        renderer.render(output_path, scale: scale, shadow: shadow, transparent: transparent)
        images << { path: output_path, delay: frame[:delay] }
      end

      complete = true
      images
    ensure
      FileUtils.rm_rf(temp_dir) if temp_dir && !complete
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
      if %w[mp4 webm apng].include?(format)
        DependencyChecker.ensure_ffmpeg!
        return FfmpegEncoder.encode(
          images,
          output_path,
          format: format,
          command: DependencyChecker.ffmpeg_path,
          framerate: config.animation[:framerate],
          playback_speed: config.animation[:playback_speed],
          loop: config.animation[:loop],
          loop_count: config.animation[:loop_count],
          apng_prediction: config.animation[:apng_prediction]
        )
      end

      palette = GifPalette.new(config: config, theme: theme) if format == "gif"
      ImageMagickCommandBuilder.convert do |convert|
        convert.dispose "none" if format == "gif"
        convert.loop animation_loop_count

        animation_entries(images).each do |delay, img|
          convert.delay delay
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
        convert.layers "optimize" if config.animation[:gif_optimize]
      when "webp"
        convert.define "webp:lossless=#{config.animation[:webp_lossless]}"
        convert.define "webp:method=#{config.animation[:webp_method]}"
        convert.define "webp:near-lossless=#{config.animation[:webp_near_lossless]}"
        convert.quality config.animation[:webp_quality]
      end
    end

    def animation_loop_count
      config.animation[:loop_count] || (config.animation[:loop] ? 0 : 1)
    end

    def cleanup_temp_files(images)
      temp_dir = File.dirname(images.first[:path]) if images.any?
      FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
    end

    def write_png_sequence(images, output_path)
      if Dir.exist?(output_path) && !replaceable_sequence_directory?(output_path)
        raise FileSystemError, "Refusing to replace a non-Shellfie directory: #{output_path}"
      end

      parent = File.dirname(File.expand_path(output_path))
      FileUtils.mkdir_p(parent)
      temporary = Dir.mktmpdir(".shellfie-sequence-", parent)
      frames = images.each_with_index.map do |image, index|
        filename = "frame_#{format("%04d", index)}.png"
        FileUtils.cp(image[:path], File.join(temporary, filename))
        { file: filename, delay_ms: image[:delay] / config.animation[:playback_speed] }
      end
      File.write(File.join(temporary, "timeline.json"), JSON.pretty_generate(version: 1, frames: frames))
      backup = "#{temporary}-previous"
      File.rename(output_path, backup) if File.exist?(output_path)
      File.rename(temporary, output_path)
      FileUtils.rm_rf(backup)
      output_path
    rescue StandardError
      File.rename(backup, output_path) if backup && File.exist?(backup) && !File.exist?(output_path)
      raise
    ensure
      FileUtils.rm_rf(temporary) if temporary && Dir.exist?(temporary)
      FileUtils.rm_rf(backup) if backup && File.exist?(backup)
    end

    def replaceable_sequence_directory?(path)
      entries = Dir.children(path)
      return true if entries.empty?
      return false unless entries.include?("timeline.json")

      entries.all? { |entry| entry == "timeline.json" || entry.match?(/\Aframe_\d{4}\.png\z/) }
    end

    def animation_delays(images)
      elapsed = 0.0
      emitted = 0
      images.map do |image|
        elapsed += image[:delay] / config.animation[:playback_speed]
        target = [(elapsed / 10.0).round, emitted + 1].max
        (target - emitted).tap { emitted = target }
      end
    end

    def animation_entries(images)
      target_ticks = [(images.sum { |image| image[:delay] } / config.animation[:playback_speed] / 10.0).round, 1].max
      return animation_delays(images).zip(images) if target_ticks >= images.size

      elapsed = 0.0
      ends = images.map { |image| elapsed += image[:delay] / config.animation[:playback_speed] }
      indexes = (1..target_ticks).map do |tick|
        ends.index { |finish| finish >= tick * 10 } || images.size - 1
      end
      indexes[-1] = images.size - 1
      indexes.chunk(&:itself).map { |index, ticks| [ticks.size, images[index]] }
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

    def playback_frames(frames)
      frames = frames.reverse if config.animation[:direction] == "reverse"
      offset = config.animation[:loop_offset]
      if offset >= frames.size
        raise ValidationError, "animation.loop_offset must be less than the #{frames.size} rendered frames"
      end
      frames = frames.rotate(offset)
      return frames unless config.animation[:direction] == "ping_pong" && frames.size > 2

      frames + frames[1...-1].reverse
    end

    def validate_workload!(frames, scale:, shadow:)
      speed = Rational(config.animation[:playback_speed].to_s)
      encoded_frames = (frames.sum { |frame| frame[:delay] } * config.animation[:framerate] / (1_000 * speed)).ceil
      if encoded_frames > config.limits[:max_render_frames]
        raise ResourceLimitError,
              "Animation timeline would encode #{encoded_frames} frames (max #{config.limits[:max_render_frames]})"
      end

      visible_lines = fixed_visible_lines(frames)
      max_pixels = frames.map do |frame|
        frame_config = create_frame_config(frame[:lines], window_overrides: { visible_lines: visible_lines }.merge(frame[:window] || {}))
        geometry = Renderer.new(frame_config).estimate(scale: scale, shadow: shadow)
        geometry[:canvas_width] * geometry[:canvas_height]
      end.max || 0
      total_pixels = max_pixels * frames.size
      if total_pixels > config.limits[:max_total_pixels]
        raise ResourceLimitError,
              "Animation workload is too large (#{total_pixels} pixels, max #{config.limits[:max_total_pixels]})"
      end

      estimated_bytes = total_pixels * 4
      return if estimated_bytes <= config.limits[:max_temp_bytes]

      raise ResourceLimitError,
            "Animation temporary data is too large (#{estimated_bytes} bytes, max #{config.limits[:max_temp_bytes]})"
    end

    def fixed_visible_lines(frames)
      config.window[:visible_lines] || [frames.map { |frame| frame[:lines].size }.max.to_i, 1].max
    end

  end
end
