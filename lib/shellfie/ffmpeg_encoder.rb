# frozen_string_literal: true

require "open3"
require "tempfile"
require_relative "errors"

module Shellfie
  class FfmpegEncoder
    def self.encode(images, output_path, format:, command:, framerate:, playback_speed:, loop:)
      list = Tempfile.new(["shellfie-frames", ".txt"])
      images.each do |image|
        list.puts "file '#{image[:path].gsub("'", "'\\''")}'"
        list.puts "duration #{image[:delay] / 1_000.0 / playback_speed}"
      end
      list.puts "file '#{images.last[:path].gsub("'", "'\\''")}'" unless format == "apng"
      list.close

      total_duration = images.sum { |image| image[:delay] } / 1_000.0 / playback_speed
      filters = ["fps=#{framerate}", "pad=ceil(iw/2)*2:ceil(ih/2)*2"]
      codec = case format
              when "mp4" then %w[-c:v libx264 -pix_fmt yuv420p -movflags +faststart]
              when "webm" then %w[-c:v libvpx-vp9 -pix_fmt yuva420p]
              when "apng"
                final_delay = images.last[:delay] / 1_000.0 / playback_speed
                ["-plays", loop ? "0" : "1", "-final_delay", final_delay.to_s, "-f", "apng"]
              else raise RenderError, "Unsupported ffmpeg format: #{format}"
              end
      timing = if format == "apng"
                 %w[-fps_mode vfr]
               else
                 ["-vf", filters.join(","), "-fps_mode", "cfr", "-t", total_duration.to_s]
               end
      _stdout, stderr, status = Open3.capture3(command, "-y", "-f", "concat", "-safe", "0", "-i", list.path,
                                               *timing, *codec, output_path)
      raise RenderError, "ffmpeg encode failed: #{stderr}" unless status.success?

      output_path
    ensure
      list&.close!
    end
  end
end
