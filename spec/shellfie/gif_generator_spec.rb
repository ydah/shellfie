# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::GifGenerator do
  describe "frame building" do
    it "builds a single GIF frame from static lines" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "done")])
      generator = described_class.new(config)

      frames = generator.send(:build_animation_frames)

      expect(frames.size).to eq(1)
      expect(frames.first[:lines].first.output).to eq("done")
      expect(frames.first[:delay]).to eq(config.animation[:final_delay])
    end

    it "adds command pause frames with cursor blinking" do
      config = Shellfie::Config.new(
        animation: { typing_speed: 20, command_delay: 100, cursor_blink: true },
        frames: [Shellfie::Frame.new(prompt: "$ ", type: "echo ok")]
      )
      generator = described_class.new(config)

      frames = generator.send(:build_animation_frames)

      expect(frames.map { |frame| frame[:delay] }).to include(50)
    end

    it "clamps GIF delay to at least one tick" do
      config = Shellfie::Config.new(frames: [Shellfie::Frame.new(prompt: "$ ", type: "x")])
      generator = described_class.new(config)

      expect(generator.send(:gif_delay, 0)).to eq(1)
    end

    it "uses configured cursor glyphs" do
      config = Shellfie::Config.new(
        cursor: { style: "bar", color: "#ff0000" },
        frames: [Shellfie::Frame.new(prompt: "$ ", type: "x")]
      )
      generator = described_class.new(config)

      expect(generator.send(:cursor_text)).to include("|")
      expect(generator.send(:cursor_text)).to include("\e[38;2;255;0;0m")
    end
  end
end
