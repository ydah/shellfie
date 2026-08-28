# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"

RSpec.describe Shellfie::TranscriptRenderer do
  it "writes the final semantic transcript as text and JSON" do
    config = Shellfie::Config.new(
      lines: [Shellfie::Line.new(output: "ready")],
      animation: { final_delay: 0 },
      frames: [Shellfie::Frame.new(prompt: "$ ", type: "go", delay: 1)]
    )

    Dir.mktmpdir do |dir|
      text_path = File.join(dir, "session.txt")
      json_path = File.join(dir, "session.json")
      described_class.new(config).render(text_path, format: "txt")
      described_class.new(config).render(json_path, format: "json")

      expect(File.read(text_path)).to eq("ready\n$ go\n")
      expect(JSON.parse(File.read(json_path))).to include("title" => "Terminal", "version" => 1)
    end
  end
end
