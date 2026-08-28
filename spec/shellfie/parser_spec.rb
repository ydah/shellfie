# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

    it "allows YAML aliases" do
      yaml = <<~YAML
        lines:
          - &base
            prompt: "$ "
            command: "echo aliased"
          - *base
      YAML

      expect(described_class.parse_string(yaml).lines.last.command).to eq("echo aliased")
    end

    it "parses config version and color overrides" do
      yaml = <<~YAML
        version: 1
        theme: custom
        window_theme: windows
        color_scheme: dracula
        colors:
          background: "#111111"
        window_decoration:
          corner_radius: 4
        limits:
          max_lines: 100
        lines:
          - output: "test"
      YAML

      config = described_class.parse_string(yaml)

      expect(config.theme).to eq("custom")
      expect(config.window_theme).to eq("windows")
      expect(config.color_scheme).to eq("dracula")
      expect(config.colors[:background]).to eq("#111111")
      expect(config.window_decoration[:corner_radius]).to eq(4)
    end
  end

  describe ".parse" do
    it "raises ParseError for non-existent file" do
      expect { described_class.parse("/nonexistent/path.yml") }.to raise_error(Shellfie::ParseError, /not found/)
    end

    it "loads included YAML relative to the config file" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "base.yml"), "title: Included\n")
        config_path = File.join(dir, "terminal.yml")
        File.write(config_path, <<~YAML)
          include: base.yml
          lines:
            - output: "test"
        YAML

        expect(described_class.parse(config_path).title).to eq("Included")
      end
    end

    it "reports circular includes with the include chain" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a.yml"), "include: b.yml\nlines:\n  - output: a\n")
        File.write(File.join(dir, "b.yml"), "include: a.yml\n")

        expect { described_class.parse(File.join(dir, "a.yml")) }
          .to raise_error(Shellfie::ParseError, /a\.yml -> b\.yml -> a\.yml/)
      end
    end

    it "rejects non-string include paths" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "a.yml")
        File.write(path, "include: 123\nlines:\n  - output: a\n")

        expect { described_class.parse(path) }.to raise_error(Shellfie::ParseError, /path must be a string/)
      end
    end

    it "reports source locations and typo suggestions" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.yml")
        File.write(path, "theem: macos\nlines:\n  - output: ok\n")

        expect { described_class.parse(path) }
          .to raise_error(Shellfie::ValidationError, /bad\.yml:1:.*theem -> theme/)
      end
    end

    it "can restrict includes to the root configuration directory" do
      Dir.mktmpdir do |dir|
        root = File.join(dir, "root")
        Dir.mkdir(root)
        File.write(File.join(dir, "outside.yml"), "title: Outside\n")
        path = File.join(root, "config.yml")
        File.write(path, "include: ../outside.yml\ninclude_policy: root\nlines:\n  - output: ok\n")

        expect { described_class.parse(path) }.to raise_error(Shellfie::ParseError, /escapes the configuration root/)
      end
    end
  end
end
