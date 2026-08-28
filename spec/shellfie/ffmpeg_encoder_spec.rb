# frozen_string_literal: true

require "spec_helper"
require "shellfie/ffmpeg_encoder"

RSpec.describe Shellfie::FfmpegEncoder do
  it "encodes video at the requested rate and playback speed" do
    status = instance_double(Process::Status, success?: true)
    captured = nil
    allow(Open3).to receive(:capture3) do |*args|
      captured = [args, File.read(args[args.index("-i") + 1])]
      ["", "", status]
    end

    described_class.encode(
      [{ path: "/tmp/frame.png", delay: 1_000 }],
      "/tmp/out.mp4",
      format: "mp4",
      command: "ffmpeg",
      framerate: 24,
      playback_speed: 2.0,
      loop: false
    )

    args, concat = captured
    expect(args).to include("-vf", "fps=24,pad=ceil(iw/2)*2:ceil(ih/2)*2", "-fps_mode", "cfr", "-t", "0.5")
    expect(concat).to include("duration 0.5")
  end

  it "preserves the final APNG hold and loop setting" do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(["", "", status])

    described_class.encode(
      [{ path: "/tmp/frame.png", delay: 750 }],
      "/tmp/out.apng",
      format: "apng",
      command: "ffmpeg",
      framerate: 30,
      playback_speed: 1.5,
      loop: true
    )

    expect(Open3).to have_received(:capture3).with(
      "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", anything,
      "-fps_mode", "vfr",
      "-plays", "0", "-final_delay", "0.5", "-f", "apng", "/tmp/out.apng"
    )
  end

  it "does not duplicate the APNG tail before applying its final delay" do
    status = instance_double(Process::Status, success?: true)
    concat = nil
    allow(Open3).to receive(:capture3) do |*args|
      concat = File.read(args[args.index("-i") + 1])
      ["", "", status]
    end

    described_class.encode(
      [{ path: "/tmp/frame.png", delay: 750 }],
      "/tmp/out.apng",
      format: "apng",
      command: "ffmpeg",
      framerate: 30,
      playback_speed: 1.0,
      loop: true
    )

    expect(concat.scan(/^file /).size).to eq(1)
  end
end
