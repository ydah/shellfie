# frozen_string_literal: true

require "rbconfig"
require "open3"

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

        raise DependencyError, "ffmpeg not found; install ffmpeg to generate MP4 or WebM"
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
        [
          check("Ruby", RUBY_VERSION, Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0")),
          check("ImageMagick", details[:version] || "not found", imagemagick_available?),
          check("Image formats", details[:formats].empty? ? "unavailable" : details[:formats].join(", "),
                (required_formats - details[:formats]).empty?),
          check("Fonts", details[:font_count].to_s, details[:font_count].positive?),
          check("ffmpeg", ffmpeg_path || "not found", !ffmpeg_path.nil?),
          check("Writable output", output_dir, File.writable?(output_dir)),
          check("Encoding", Encoding.default_external.name, true)
        ]
      end

      def imagemagick_details
        return { version: nil, formats: [], font_count: 0 } unless imagemagick_available?

        version_output, = Open3.capture3(imagemagick_path, "-version")
        formats_output, = Open3.capture3(imagemagick_path, "-list", "format")
        fonts_output, = Open3.capture3(imagemagick_path, "-list", "font")
        {
          version: version_output.lines.first&.strip,
          formats: required_formats.select { |format| formats_output.match?(/^\s*#{format}\*?\s/im) },
          font_count: fonts_output.scan(/^\s*Font:/).size
        }
      rescue SystemCallError
        { version: nil, formats: [], font_count: 0 }
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
        %w[PNG GIF WEBP APNG SVG]
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
