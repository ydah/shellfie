# frozen_string_literal: true

require "rbconfig"
require "open3"
require "tempfile"
require_relative "rendering/font_resolver"

module Shellfie
  class DependencyChecker
    IMAGE_MAGICK_COMMANDS = %w[magick convert].freeze

    class << self
      def imagemagick_path
        @imagemagick_path ||= find_executable(IMAGE_MAGICK_COMMANDS)
      end

      def imagemagick_available?
        !imagemagick_path.to_s.empty?
      end

      def ffmpeg_path
        @ffmpeg_path ||= find_executable(%w[ffmpeg], verify_imagemagick: false)
      end

      def ensure_ffmpeg!
        return if ffmpeg_path

        raise DependencyError, "ffmpeg not found; install ffmpeg to generate APNG, MP4, or WebM"
      end

      def ffmpeg_version
        return unless ffmpeg_path

        output, = Open3.capture3(ffmpeg_path, "-version")
        output.lines.first&.strip
      rescue SystemCallError
        nil
      end

      def ensure_imagemagick!
        return if imagemagick_available?

        raise DependencyError, <<~MSG
          ImageMagick not found
            → Please install ImageMagick: brew install imagemagick
            → Or visit: https://imagemagick.org/script/download.php
        MSG
      end

      def configure_mini_magick!(timeout: 30)
        return unless defined?(MiniMagick) && MiniMagick.respond_to?(:timeout=)

        MiniMagick.timeout = timeout
      end

      def doctor(output_dir: Dir.pwd)
        details = imagemagick_details
        video_version = ffmpeg_version
        [
          check("Ruby", RUBY_VERSION, Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0")),
          check("ImageMagick", details[:version] || "not found", imagemagick_available?),
          check("Image formats", details[:formats].empty? ? "unavailable" : details[:formats].join(", "),
                (required_formats - details[:formats]).empty?),
          check("Image render", details[:render_ok] ? "1x1 PNG generated" : "failed", details[:render_ok]),
          check("Fonts", details[:font_count].to_s, details[:font_count].positive?),
          check("Security policy", details[:policy] || "unavailable", !details[:policy].nil?),
          check("ffmpeg (optional)", video_version || "not found; required only for APNG/MP4/WebM", true),
          check("Writable output", output_dir, File.writable?(output_dir)),
          check("Encoding", Encoding.default_external.name, true)
        ]
      end

      def imagemagick_details
        return { version: nil, formats: [], font_count: 0, render_ok: false, policy: nil } unless imagemagick_available?

        version_output, _error, version_status = Open3.capture3(imagemagick_path, "-version")
        formats_output, _error, formats_status = Open3.capture3(imagemagick_path, "-list", "format")
        fonts_output, _error, fonts_status = Open3.capture3(imagemagick_path, "-list", "font")
        policy_output, _error, policy_status = Open3.capture3(imagemagick_path, "-list", "policy")
        {
          version: version_status.success? ? version_output.lines.first&.strip : nil,
          formats: formats_status.success? ? required_formats.select { |format| formats_output.match?(/^\s*#{format}\*?\s/im) } : [],
          font_count: (fonts_status.success? ? fonts_output.scan(/^\s*Font:/).size : 0) +
            FontResolver::FONT_FILES.values.uniq.count { |path| File.file?(path) },
          render_ok: render_smoke_test,
          policy: policy_status.success? ? "#{policy_output.scan(/^\s*Policy:/).size} rules loaded" : nil
        }
      rescue SystemCallError
        { version: nil, formats: [], font_count: 0, render_ok: false, policy: nil }
      end

      private

      def check(name, detail, ok)
        { name: name, detail: detail, ok: ok }
      end

      def find_executable(names, verify_imagemagick: true)
        paths = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
        extensions = executable_extensions

        names.each do |name|
          paths.each do |path|
            extensions.each do |extension|
              candidate = File.join(path, "#{name}#{extension}")
              next unless File.file?(candidate) && File.executable?(candidate)
              return candidate unless verify_imagemagick
              return candidate if imagemagick_executable?(candidate)
            end
          end
        end

        nil
      end

      def imagemagick_executable?(candidate)
        output, = Open3.capture3(candidate, "-version")
        output.include?("ImageMagick")
      rescue SystemCallError
        false
      end

      def required_formats
        %w[PNG GIF WEBP SVG]
      end

      def render_smoke_test
        Tempfile.create(["shellfie-doctor", ".png"]) do |file|
          _output, _error, status = Open3.capture3(imagemagick_path, "-size", "1x1", "xc:none", file.path)
          return status.success? && File.binread(file.path, 8) == "\x89PNG\r\n\x1a\n".b
        end
      rescue SystemCallError, EOFError
        false
      end

      def executable_extensions
        return [""] unless windows?

        ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";")
      end

      def windows?
        RbConfig::CONFIG["host_os"].match?(/mswin|mingw|cygwin/i)
      end
    end
  end
end
