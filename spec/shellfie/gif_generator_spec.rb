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

    it "preserves semantic prompt and command colors in animation frames" do
      config = Shellfie::Config.new(
        frames: [
          Shellfie::Frame.new(prompt: "$ ", type: "echo ok", prompt_color: "green", command_color: "#ff00ff")
        ]
      )
      generator = described_class.new(config)

      command_line = generator.send(:build_animation_frames)
        .flat_map { |frame| frame[:lines] }
        .find { |line| line.command == "echo ok" }

      expect(command_line.prompt_color).to eq("green")
      expect(command_line.command_color).to eq("#ff00ff")
    end

    it "eases output delays for scrolling output" do
      config = Shellfie::Config.new(
        animation: { output_delay: 100, scroll_easing: "ease_out", final_delay: 0 },
        frames: [Shellfie::Frame.new(output: "one\ntwo\nthree")]
      )
      generator = described_class.new(config)

      delays = generator.send(:build_animation_frames).map { |frame| frame[:delay] }

      expect(delays.first).to be > delays.last
    end

    it "adds eased scroll offsets when output exceeds visible lines" do
      config = Shellfie::Config.new(
        window: { visible_lines: 2 },
        animation: { output_delay: 100, scroll_easing: "ease_out", final_delay: 0 },
        frames: [Shellfie::Frame.new(output: "one\ntwo\nthree")]
      )
      generator = described_class.new(config)

      offsets = generator.send(:build_animation_frames).filter_map { |frame| frame.dig(:window, :scroll_offset) }

      expect(offsets.size).to be > 1
      expect(offsets).to eq(offsets.sort)
      expect(offsets.last).to eq(1.0)
    end

    it "passes per-frame window overrides into rendered frame configs" do
      config = Shellfie::Config.new(frames: [Shellfie::Frame.new(output: "one")])
      generator = described_class.new(config)

      frame_config = generator.send(
        :create_frame_config,
        [Shellfie::Line.new(output: "one")],
        window_overrides: { scroll_offset: 0.5 }
      )

      expect(frame_config.window[:scroll_offset]).to eq(0.5)
    end
  end
end
