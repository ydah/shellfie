# frozen_string_literal: true

require "open3"
require "tempfile"
require_relative "errors"

module Shellfie
  class FfmpegEncoder
    def self.encode(images, output_path, format:, command:)
      list = Tempfile.new(["shellfie-frames", ".txt"])
      images.each do |image|
        list.puts "file '#{image[:path].gsub("'", "'\\''")}'"
        list.puts "duration #{image[:delay] / 1_000.0}"
      end
      list.puts "file '#{images.last[:path].gsub("'", "'\\''")}'"
      list.close

      codec = format == "mp4" ? %w[-c:v libx264 -pix_fmt yuv420p -movflags +faststart] : %w[-c:v libvpx-vp9 -pix_fmt yuva420p]
      _stdout, stderr, status = Open3.capture3(command, "-y", "-f", "concat", "-safe", "0", "-i", list.path,
                                               *codec, output_path)
      raise RenderError, "ffmpeg encode failed: #{stderr}" unless status.success?

      output_path
    ensure
      list&.close!
    end
  end
end
