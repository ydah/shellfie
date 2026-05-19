# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::AnimationTimeline do
  describe "#each" do
    it "emits command, output, and pause events in frame order" do
      config = Shellfie::Config.new(
        frames: [
          Shellfie::Frame.new(prompt: "$ ", type: "echo ok"),
          Shellfie::Frame.new(output: "ok"),
          Shellfie::Frame.new(delay: 250)
        ]
      )

      events = described_class.new(config).each.to_a

      expect(events.map(&:kind)).to eq(%i[command output pause])
      expect(events.map(&:frame)).to eq(config.frames)
    end
  end
end
