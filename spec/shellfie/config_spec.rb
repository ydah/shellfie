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
