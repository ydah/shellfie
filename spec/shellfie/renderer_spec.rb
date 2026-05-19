# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::Renderer do
  describe "line preparation" do
    it "preserves trailing output lines" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "one\n")])
      renderer = described_class.new(config)

      lines = renderer.send(:build_lines)

      expect(lines.size).to eq(2)
      expect(lines.first[:segments].first.text).to eq("one")
      expect(lines.last[:segments]).to be_empty
    end

    it "applies semantic prompt and command colors" do
      config = Shellfie::Config.new(
        lines: [
          Shellfie::Line.new(prompt: "$ ", command: "echo test", prompt_color: :green, command_color: "#ff00ff")
        ]
      )
      renderer = described_class.new(config)

      segments = renderer.send(:build_lines).first[:segments]

      expect(segments[0].foreground).to eq(:green)
      expect(segments[1].foreground).to eq("#ff00ff")
    end

    it "wraps long lines when configured" do
      config = Shellfie::Config.new(
        window: { width: 140, padding: 0, overflow: "wrap" },
        font: { size: 20 },
        lines: [Shellfie::Line.new(output: "abcdefghijklmnopqrstuvwxyz")]
      )
      renderer = described_class.new(config)

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: false)

      expect(geometry[:lines].size).to be > 1
    end

    it "clips long lines by default" do
      config = Shellfie::Config.new(
        window: { width: 140, padding: 0 },
        font: { size: 20 },
        lines: [Shellfie::Line.new(output: "abcdefghijklmnopqrstuvwxyz")]
      )
      renderer = described_class.new(config)

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: false)
      text = geometry[:lines].first[:segments].map(&:text).join

      expect(text.length).to be < 26
    end

    it "uses no implicit margin for exact-size output" do
      config = Shellfie::Config.new(
        window: { exact_size: true },
        lines: [Shellfie::Line.new(output: "test")]
      )
      renderer = described_class.new(config)

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: true)

      expect(geometry[:margin]).to eq(0)
      expect(geometry[:canvas_width]).to eq(config.window[:width])
    end
  end
end
