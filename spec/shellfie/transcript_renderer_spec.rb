# frozen_string_literal: true

require "json"
require "spec_helper"
require "shellfie/transcript_renderer"
require "tmpdir"

RSpec.describe Shellfie::TranscriptRenderer do
  it "writes the final semantic transcript as text and JSON" do
    config = Shellfie::Config.new(
      lines: [Shellfie::Line.new(output: "\e[31mready\e[0m")],
      animation: { final_delay: 0 },
      frames: [Shellfie::Frame.new(prompt: "$ ", type: "go", delay: 1)]
    )

    Dir.mktmpdir do |dir|
      text_path = File.join(dir, "session.txt")
      json_path = File.join(dir, "session.json")
      described_class.new(config).render(text_path, format: "txt")
      described_class.new(config).render(json_path, format: "json")

      expect(File.read(text_path)).to eq("ready\n$ go\n")
      document = JSON.parse(File.read(json_path))
      expect(document).to include("title" => "Terminal", "version" => 1)
      expect(document.dig("lines", 0, "output")).to eq("ready")
    end
  end


  it "preserves ANSI and writes asciicast v2 events" do
    config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "\e[31mred\e[0m")])
    Dir.mktmpdir do |dir|
      ansi = File.join(dir, "out.ansi")
      cast = File.join(dir, "out.cast")
      described_class.new(config).render(ansi, format: "ansi")
      described_class.new(config).render(cast, format: "asciicast")

      expect(File.binread(ansi)).to include("\e[31mred")
      lines = File.readlines(cast)
      expect(JSON.parse(lines.first)).to include("version" => 2)
      expect(JSON.parse(lines.last)).to include(0.0, "o")
    end
  end
end
