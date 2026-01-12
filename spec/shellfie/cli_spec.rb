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
      expect { cli.run }.to output(/macos/).to_stdout
    end

    it "outputs sample config with init" do
      cli = described_class.new(["init"])
      expect { cli.run }.to output(/theme: macos/).to_stdout
    end

    it "exits with error for unknown command" do
      cli = described_class.new(["unknown"])
      expect { cli.run }.to output(/Unknown command/).to_stdout.and raise_error(SystemExit)
    end
  end
end
