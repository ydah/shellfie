# frozen_string_literal: true

require "rbconfig"

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
        [
          check("Ruby", RUBY_VERSION, Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0")),
          check("ImageMagick", imagemagick_path || "not found", imagemagick_available?),
          check("Writable output", output_dir, File.writable?(output_dir)),
          check("Encoding", Encoding.default_external.name, true)
        ]
      end

      private

      def check(name, detail, ok)
        { name: name, detail: detail, ok: ok }
      end

      def find_executable(names)
        paths = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
        extensions = executable_extensions

        names.each do |name|
          paths.each do |path|
            extensions.each do |extension|
              candidate = File.join(path, "#{name}#{extension}")
              return candidate if File.file?(candidate) && File.executable?(candidate)
            end
          end
        end

        nil
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
