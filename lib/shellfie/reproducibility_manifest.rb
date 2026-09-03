# frozen_string_literal: true

require 'digest'
require 'json'
require 'rbconfig'

module Shellfie
  module ReproducibilityManifest
    def self.build(config, output_path:, format:)
      renderer = Renderer.new(config)
      {
        schema: 1,
        config_sha256: Digest::SHA256.hexdigest(JSON.generate(config.to_h)),
        output: output_path,
        output_sha256: output_digest(output_path),
        format: format,
        ruby: RUBY_DESCRIPTION,
        platform: RbConfig::CONFIG['host_os'],
        unicode: {
          version: Terminal::TextMetrics::UNICODE_VERSION,
          width_table: Terminal::TextMetrics::WIDTH_TABLE_VERSION,
          ambiguous_width: config.window[:ambiguous_width]
        },
        imagemagick: DependencyChecker.imagemagick_details[:version],
        ffmpeg: DependencyChecker.ffmpeg_version,
        fonts: renderer.font_details
      }
    end

    def self.output_digest(path)
      return Digest::SHA256.file(path).hexdigest if File.file?(path)
      return unless File.directory?(path)

      digest = Digest::SHA256.new
      Dir.glob(File.join(path, '**', '*'), File::FNM_DOTMATCH).select { |entry| File.file?(entry) }.sort.each do |entry|
        digest << entry.delete_prefix("#{path}#{File::SEPARATOR}") << "\0" << Digest::SHA256.file(entry).digest
      end
      digest.hexdigest
    end
  end
end
