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
