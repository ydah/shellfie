# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::Config do
  describe "#initialize" do
    it "sets default values" do
      config = described_class.new

      expect(config.theme).to eq("macos")
      expect(config.window[:width]).to eq(600)
      expect(config.window[:padding]).to eq(20)
      expect(config.font[:family]).to eq("Monaco")
      expect(config.font[:size]).to eq(14)
    end

    it "merges provided options with defaults" do
      config = described_class.new(
        theme: "ubuntu",
        window: { width: 800 }
      )

      expect(config.theme).to eq("ubuntu")
      expect(config.window[:width]).to eq(800)
      expect(config.window[:padding]).to eq(20)
    end

    it "deep-freezes defaults and instance state" do
      config = described_class.new

      expect(config.window).to be_frozen
      expect { config.window[:width] = 700 }.to raise_error(FrozenError)
      expect(described_class.new.window[:width]).to eq(600)
    end

    it "validates themes" do
      expect { described_class.new(theme: "missing") }.to raise_error(Shellfie::ValidationError, /Invalid theme/)
    end

    it "validates window dimensions" do
      expect { described_class.new(window: { width: 0 }) }.to raise_error(Shellfie::ValidationError, /window.width/)
      expect { described_class.new(window: { padding: -1 }) }.to raise_error(Shellfie::ValidationError, /window.padding/)
      expect { described_class.new(window: { width: 200, padding: 41 }) }.to raise_error(Shellfie::ValidationError, /padding/)
    end

    it "validates opacity and overflow mode" do
      expect { described_class.new(window: { opacity: 1.5 }) }.to raise_error(Shellfie::ValidationError, /window.opacity/)
      expect { described_class.new(window: { scroll_offset: 1.1 }) }.to raise_error(Shellfie::ValidationError, /scroll_offset/)
      expect { described_class.new(window: { overflow: "spill" }) }.to raise_error(Shellfie::ValidationError, /window.overflow/)
    end

    it "validates boolean settings" do
      expect { described_class.new(window: { wrap: "yes" }) }.to raise_error(Shellfie::ValidationError, /window.wrap/)
      expect { described_class.new(animation: { loop: "yes" }) }.to raise_error(Shellfie::ValidationError, /animation.loop/)
      expect { described_class.new(headless: "yes") }.to raise_error(Shellfie::ValidationError, /headless/)
    end

    it "validates font names and gradients" do
      expect { described_class.new(font: { family: 123 }) }.to raise_error(Shellfie::ValidationError, /font.family/)
      expect do
        described_class.new(window: { background_gradient: ["#000000"] })
      end.to raise_error(Shellfie::ValidationError, /background_gradient/)
    end

    it "validates custom decoration and color value types" do
      expect do
        described_class.new(window_decoration: { title_bar_height: "nope" })
      end.to raise_error(Shellfie::ValidationError, /title_bar_height/)
      expect { described_class.new(colors: { foreground: 1 }) }.to raise_error(Shellfie::ValidationError, /colors/)
    end

    it "validates animation settings" do
      expect { described_class.new(animation: { typing_chunk_size: 0 }) }.to raise_error(Shellfie::ValidationError, /typing_chunk_size/)
      expect { described_class.new(animation: { typing_jitter: 2.0 }) }.to raise_error(Shellfie::ValidationError, /typing_jitter/)
      expect { described_class.new(animation: { palette: "bad" }) }.to raise_error(Shellfie::ValidationError, /animation.palette/)
      expect { described_class.new(animation: { scroll_easing: "bad" }) }.to raise_error(Shellfie::ValidationError, /scroll_easing/)
    end

    it "validates cursor style" do
      expect { described_class.new(cursor: { style: "box" }) }.to raise_error(Shellfie::ValidationError, /cursor.style/)
    end

    it "normalizes string keys" do
      config = described_class.new("window" => { "width" => 800 }, "lines" => [])

      expect(config.window[:width]).to eq(800)
    end

    it "validates config version" do
      expect { described_class.new(version: 2) }.to raise_error(Shellfie::ValidationError, /Unsupported config version/)
    end

    it "enforces resource limits" do
      expect do
        described_class.new(limits: { max_lines: 1 }, lines: [Shellfie::Line.new(output: "1"), Shellfie::Line.new(output: "2")])
      end.to raise_error(Shellfie::ResourceLimitError, /Too many lines/)
    end

    it "keeps color customization immutable" do
      config = described_class.new(colors: { background: "#000000" })

      expect(config.colors).to be_frozen
      expect(config.colors[:background]).to eq("#000000")
    end
  end

  describe "#static?" do
    it "returns true when frames are empty" do
      config = described_class.new(lines: [])

      expect(config.static?).to be true
    end

    it "returns false when frames are present" do
      config = described_class.new(frames: [Shellfie::Frame.new])

      expect(config.static?).to be false
    end
  end

  describe "#animated?" do
    it "returns true when frames are present" do
      config = described_class.new(frames: [Shellfie::Frame.new])

      expect(config.animated?).to be true
    end

    it "returns false when frames are empty" do
      config = described_class.new

      expect(config.animated?).to be false
    end
  end
end
