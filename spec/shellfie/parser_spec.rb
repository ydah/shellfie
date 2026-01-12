# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::Parser do
  describe ".parse_string" do
    it "parses simple config" do
      yaml = <<~YAML
        theme: macos
        title: "Test Terminal"
        lines:
          - prompt: "$ "
            command: "echo hello"
      YAML

      config = described_class.parse_string(yaml)

      expect(config.theme).to eq("macos")
      expect(config.title).to eq("Test Terminal")
      expect(config.lines.size).to eq(1)
      expect(config.lines.first.prompt).to eq("$ ")
      expect(config.lines.first.command).to eq("echo hello")
    end

    it "applies default values" do
      yaml = <<~YAML
        title: "Test"
        lines:
          - prompt: "$ "
            command: "test"
      YAML

      config = described_class.parse_string(yaml)

      expect(config.theme).to eq("macos")
      expect(config.window[:width]).to eq(600)
      expect(config.window[:padding]).to eq(20)
    end

    it "raises ParseError for invalid YAML" do
      yaml = "{ invalid: yaml: content }"

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ParseError)
    end

    it "raises ValidationError for empty config" do
      yaml = ""

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError)
    end

    it "raises ValidationError for invalid theme" do
      yaml = <<~YAML
        theme: nonexistent
        lines:
          - prompt: "$ "
            command: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /Invalid theme/)
    end

    it "parses output lines" do
      yaml = <<~YAML
        title: "Test"
        lines:
          - output: |
              Line 1
              Line 2
      YAML

      config = described_class.parse_string(yaml)

      expect(config.lines.first.output).to include("Line 1")
      expect(config.lines.first.output).to include("Line 2")
    end

    it "parses animation frames" do
      yaml = <<~YAML
        title: "Test"
        animation:
          typing_speed: 100
          loop: true
        frames:
          - prompt: "$ "
            type: "echo test"
            delay: 500
      YAML

      config = described_class.parse_string(yaml)

      expect(config.animated?).to be true
      expect(config.frames.size).to eq(1)
      expect(config.frames.first.type).to eq("echo test")
      expect(config.frames.first.delay).to eq(500)
    end
  end

  describe ".parse" do
    it "raises ParseError for non-existent file" do
      expect { described_class.parse("/nonexistent/path.yml") }.to raise_error(Shellfie::ParseError, /not found/)
    end
  end
end
