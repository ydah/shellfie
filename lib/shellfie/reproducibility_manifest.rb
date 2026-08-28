# frozen_string_literal: true

require "digest"
require "json"
require "rbconfig"

module Shellfie
  class ReproducibilityManifest
    def self.build(config, output_path:, format:)
      renderer = Renderer.new(config)
      {
        schema: 1,
        config_sha256: Digest::SHA256.hexdigest(JSON.generate(config.to_h)),
        output: output_path,
        output_sha256: File.file?(output_path) ? Digest::SHA256.file(output_path).hexdigest : nil,
        format: format,
        ruby: RUBY_DESCRIPTION,
        platform: RbConfig::CONFIG["host_os"],
        imagemagick: DependencyChecker.imagemagick_details[:version],
        ffmpeg: DependencyChecker.ffmpeg_path,
        fonts: renderer.font_info
      }
    end
  end
end
