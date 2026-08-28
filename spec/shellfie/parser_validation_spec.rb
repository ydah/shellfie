# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::Parser do
  describe ".parse_string validation" do
    it "raises ParseError for invalid YAML" do
      expect { described_class.parse_string("{ invalid: yaml: content }") }.to raise_error(Shellfie::ParseError)
    end

    it "wraps invalid YAML aliases as ParseError" do
      expect { described_class.parse_string("lines: *missing\n") }.to raise_error(Shellfie::ParseError, /unknown anchor/i)
    end

    it "raises ValidationError for empty config" do
      expect { described_class.parse_string("") }.to raise_error(Shellfie::ValidationError)
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
      expect { described_class.parse_string("- lines\n") }.to raise_error(Shellfie::ValidationError, /YAML mapping/)
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

    it "raises ValidationError for invalid line value types" do
      yaml = <<~YAML
        lines:
          - output: 123
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /lines\[0\].output/)
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

    it "raises ValidationError for invalid frame value types" do
      yaml = <<~YAML
        frames:
          - type: ["echo"]
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /frames\[0\].type/)
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

    it "raises ValidationError for unknown color and decoration keys" do
      expect do
        described_class.parse_string("colors:\n  foregorund: '#fff'\nlines:\n  - output: test\n")
      end.to raise_error(Shellfie::ValidationError, /Unknown colors key/)

      expect do
        described_class.parse_string("window_decoration:\n  raduis: 2\nlines:\n  - output: test\n")
      end.to raise_error(Shellfie::ValidationError, /Unknown window_decoration key/)
    end

    it "raises ValidationError for window boundary values" do
      yaml = <<~YAML
        window:
          width: 120
          padding: 60
          visible_lines: 0
        lines:
          - output: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /window.visible_lines/)
    end

    it "raises ValidationError for scroll offset bounds" do
      yaml = <<~YAML
        window:
          scroll_offset: -0.01
        lines:
          - output: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /window.scroll_offset/)
    end

    it "raises ValidationError for animation boundary values" do
      yaml = <<~YAML
        animation:
          max_frames: 0
        frames:
          - output: "test"
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /animation.max_frames/)
    end

    it "raises ValidationError for invalid frame delay bounds" do
      yaml = <<~YAML
        frames:
          - delay: -1
      YAML

      expect { described_class.parse_string(yaml) }.to raise_error(Shellfie::ValidationError, /frames\[0\].delay/)
    end
  end
end
