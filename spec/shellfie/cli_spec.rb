# frozen_string_literal: true

require "spec_helper"

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
