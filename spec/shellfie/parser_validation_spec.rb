# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::Parser do
  describe ".parse_string validation" do
    it "raises ParseError for invalid YAML" do
      expect { described_class.parse_string("{ invalid: yaml: content }") }.to raise_error(Shellfie::ParseError)
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
  end
end
