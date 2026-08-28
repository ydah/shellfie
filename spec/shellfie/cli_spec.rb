# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Shellfie::CLI do
  describe "#run" do
    it "shows help with no arguments" do
      cli = described_class.new([])
      expect { cli.run }.to output(/Shellfie - Terminal screenshot-style image generator/).to_stdout
    end

    it "shows version" do
      cli = described_class.new(["version"])
      expect { cli.run }.to output(/shellfie #{Shellfie::VERSION}/).to_stdout
    end

    it "shows help with --help" do
      cli = described_class.new(["help"])
      expect { cli.run }.to output(/Usage:/).to_stdout
    end

    it "lists themes" do
      cli = described_class.new(["themes"])
      expect { cli.run }.to output(/macos.*dracula/m).to_stdout
    end

    it "outputs sample config with init" do
      cli = described_class.new(["init"])
      expect { cli.run }.to output(/theme: macos/).to_stdout
    end

    it "exits with error for unknown command" do
      cli = described_class.new(["unknown"])
      expect { cli.run }.to output(/Unknown command/).to_stderr.and raise_error(SystemExit)
    end

    it "does not mutate the provided args array" do
      args = ["version"]
      cli = described_class.new(args)

      expect { cli.run }.to output(/shellfie #{Shellfie::VERSION}/).to_stdout
      expect(args).to eq(["version"])
    end

    it "rejects invalid scale values" do
      cli = described_class.new(["generate", "config.yml", "-o", "out.png", "--scale", "0"])

      expect { cli.run }.to output(/scale must be 1, 2, or 3/).to_stderr.and raise_error(SystemExit)
    end

    it "keeps explicit WebP output static without frames or --animate" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "ok")])
      cli = described_class.new([])
      cli.instance_variable_set(:@options, { format: "webp" })

      expect(cli.send(:animation_output?, config)).to be false
    end

    it "rejects batch output collisions before rendering" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "ok")])
      allow(Shellfie::Parser).to receive(:parse).and_return(config)
      expect(Shellfie::Renderer).not_to receive(:new)

      Dir.mktmpdir("shellfie-cli-spec") do |dir|
        cli = described_class.new(["generate", "one/same.yml", "two/same.yml", "-o", "#{dir}/", "--quiet"])
        expect { cli.run }.to output(/same output/).to_stderr.and raise_error(SystemExit)
      end
    end

    it "preserves custom config fields while applying generate overrides" do
      config = Shellfie::Config.new(
        colors: { foreground: "#123456" },
        limits: { max_pixels: 2_000_000 },
        lines: [Shellfie::Line.new(output: "ok")]
      )
      renderer = instance_double(Shellfie::Renderer, render: "out.png")
      allow(Shellfie::Parser).to receive(:parse).with("config.yml").and_return(config)
      expect(Shellfie::Renderer).to receive(:new) do |render_config|
        expect(render_config.colors[:foreground]).to eq("#123456")
        expect(render_config.limits[:max_pixels]).to eq(2_000_000)
        expect(render_config.window[:width]).to eq(420)
        renderer
      end

      Dir.mktmpdir("shellfie-cli-spec") do |dir|
        output = File.join(dir, "out.png")
        cli = described_class.new(["generate", "config.yml", "-o", output, "--width", "420", "--quiet"])
        cli.run
      end
    end

    it "renders multiple configured session outputs" do
      session = Shellfie::Session.new(columns: 40, rows: 4)
      session.record("done", visible: true, status: 0)
      cli = described_class.new([])
      cli.instance_variable_set(:@options, { quiet: true })

      Dir.mktmpdir("shellfie-session-output") do |dir|
        outputs = [
          { path: File.join(dir, "session.svg"), format: "svg", scale: 2, shadow: false },
          { path: File.join(dir, "session.txt"), format: "txt" }
        ]
        cli.send(:render_session_outputs, session, outputs, base_dir: dir, theme: "macos", render: {})

        expect(File.read(outputs[0][:path])).to include("width=\"1240\"", ">done</text>")
        expect(File.read(outputs[1][:path])).to eq("done\n")
      end
    end

    it "renders a named session capture" do
      session = Shellfie::Session.new(columns: 40, rows: 4)
      session.record("first")
      session.capture("first")
      session.record("\nsecond")
      cli = described_class.new([])
      cli.instance_variable_set(:@options, { quiet: true })

      Dir.mktmpdir("shellfie-capture-output") do |dir|
        path = File.join(dir, "capture.txt")
        cli.send(
          :render_session_outputs,
          session,
          [{ path: path, format: "txt", capture: "first" }],
          base_dir: dir,
          theme: "macos",
          render: {}
        )

        expect(File.read(path)).to eq("first\n")
      end
    end

    it "does not execute replay mode as a live session" do
      cli = described_class.new(["run", "session.yml", "-o", "out.txt"])
      config = Shellfie::SessionConfig.new({ version: 2, mode: "replay", steps: [] })
      allow(Shellfie::SessionConfig).to receive(:parse).and_return(config)
      expect(Shellfie::SessionRunner).not_to receive(:new)

      expect { cli.run }.to output(/use shellfie replay/).to_stderr.and raise_error(SystemExit)
    end

    it "prints doctor checks" do
      allow(Shellfie::DependencyChecker).to receive(:doctor).and_return([
                                                                          { name: "Ruby", detail: "3.4.0", ok: true }
                                                                        ])
      cli = described_class.new(["doctor"])

      expect { cli.run }.to output(/ok\s+Ruby/).to_stdout
    end

    it "inspects a config" do
      allow(Shellfie).to receive(:inspect_config).and_return(
        config: { version: 1, title: "Test", lines: [{}], frames: [] },
        theme: "macos",
        geometry: { canvas_width: 600, canvas_height: 200 }
      )
      cli = described_class.new(["inspect", "config.yml"])

      expect { cli.run }.to output(/Estimated size: 600x200/).to_stdout
    end
  end
end
