# frozen_string_literal: true

require "json"
require "spec_helper"
require "tmpdir"
require "stringio"

RSpec.describe Shellfie::CLI do
  it "creates, formats, and compiles a config" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "terminal.yml")
      expect { described_class.new(["new", path]).run }.to output(/Created/).to_stdout
      expect { described_class.new(["format", path]).run }.to output(/Formatted|Unchanged/).to_stdout

      output = capture_stdout { described_class.new(["compile", path, "--format", "json"]).run }
      expect(JSON.parse(output)).to include("version" => 1, "theme" => "macos")
    end
  end

  it "prints schemas and shell completions" do
    expect { described_class.new(["schema", "2"]).run }.to output(/Shellfie executable session/).to_stdout
    expect { described_class.new(["completion", "bash"]).run }.to output(/complete.*shellfie/).to_stdout
    expect { described_class.new(["completion", "powershell"]).run }.to output(/Register-ArgumentCompleter/).to_stdout
  end

  it "creates every documented template" do
    Dir.mktmpdir do |dir|
      %w[static animation run tui ci theme-gallery].each do |template|
        path = File.join(dir, "#{template}.yml")
        expect { described_class.new(["new", path, "--template", template]).run }.to output(/Created/).to_stdout
        expect(File.read(path)).to include("version:")
      end
    end
  end

  it "watches included configuration files" do
    Dir.mktmpdir do |dir|
      included = File.join(dir, "included.yml")
      input = File.join(dir, "root.yml")
      File.write(included, "title: First\n")
      File.write(input, "include: included.yml\nlines:\n  - output: ok\n")
      cli = described_class.new(["watch", input, "-o", File.join(dir, "out.svg"), "--interval", "0.01"])
      generator = instance_double(described_class, run: nil)
      expect(described_class).to receive(:new).twice.and_return(generator)
      sleeps = 0
      allow(cli).to receive(:sleep) do
        sleeps += 1
        sleeps == 1 ? File.write(included, "title: Second\n") : raise(Interrupt)
      end

      expect { cli.run }.to output(/Stopped/).to_stdout
    end
  end

  it "runs version 2 sessions when an included file changes" do
    Dir.mktmpdir do |dir|
      included = File.join(dir, "steps.yml")
      input = File.join(dir, "session.yml")
      File.write(included, "version: 2\nsteps: []\n")
      File.write(input, "version: 2\ninclude: steps.yml\nsteps: []\n")
      cli = described_class.new(["watch", input, "-o", File.join(dir, "out.svg"), "--interval", "0.01"])
      generator = instance_double(described_class, run: nil)
      expect(described_class).to receive(:new).with(["run", input, "-o", File.join(dir, "out.svg"), "--force"]).and_return(generator)
      allow(cli).to receive(:sleep) { raise Interrupt }

      expect { cli.run }.to output(/Stopped/).to_stdout
    end
  end

  def capture_stdout
    original = $stdout
    output = StringIO.new
    $stdout = output
    yield
    output.string
  ensure
    $stdout = original
  end
end
