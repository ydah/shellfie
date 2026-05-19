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

    it "raises ValidationError for non-mapping YAML" do
      yaml = <<~YAML
        - lines
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /YAML mapping/)
    end

    it "raises ValidationError for unknown top-level keys" do
      yaml = <<~YAML
        commnad: typo
        lines:
          - prompt: "$ "
            command: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /Unknown configuration key/)
    end

    it "raises ValidationError for invalid line keys" do
      yaml = <<~YAML
        lines:
          - commnad: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /Unknown lines\[0\] key/)
    end

    it "raises ValidationError when lines is not an array" do
      yaml = <<~YAML
        lines:
          prompt: "$ "
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /lines must be an array/)
    end

    it "raises ValidationError for invalid frame shape" do
      yaml = <<~YAML
        frames:
          - prompt: "$ "
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /prompt requires type/)
    end

    it "raises ValidationError for unknown nested keys" do
      yaml = <<~YAML
        window:
          widht: 600
        lines:
          - output: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /Unknown window key/)
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

    it "parses semantic line colors and selection" do
      yaml = <<~YAML
        lines:
          - prompt: "$ "
            command: "echo test"
            prompt_color: green
            command_color: "#ff00ff"
            selected: true
      YAML

      config = described_class.parse_string(yaml)

      expect(config.lines.first.prompt_color).to eq("green")
      expect(config.lines.first.command_color).to eq("#ff00ff")
      expect(config.lines.first.selected).to be true
    end
  end

  describe ".parse" do
    it "raises ParseError for non-existent file" do
      expect { described_class.parse("/nonexistent/path.yml") }.to raise_error(Shellfie::ParseError, /not found/)
    end
  end
end
