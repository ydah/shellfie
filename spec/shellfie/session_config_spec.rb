# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::SessionConfig do
  it "validates and normalizes version 2 sessions" do
    config = described_class.new(
      {
        version: 2,
        terminal: { shell: "/bin/sh", columns: 80, rows: 20 },
        requires: ["ruby"],
        steps: [{ type: "echo ok", speed: "30cps" }, { key: "enter" }, "hide", "show"],
        outputs: [{ path: "out.svg", format: "svg" }]
      }
    )

    expect(config.steps.map(&:keys)).to include([:hide], [:show])
    expect(config.outputs.first[:format]).to eq("svg")
  end

  it "rejects ambiguous steps and unsafe requirement names" do
    expect do
      described_class.new({ version: 2, requires: ["ruby; rm"], steps: [{ run: "x", type: "y" }] })
    end.to raise_error(Shellfie::ValidationError)
  end

  it "validates waits, asynchronous steps, captures, and terminal bounds" do
    expect do
      described_class.new({ version: 2, terminal: { columns: 501 }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /columns/)

    expect do
      described_class.new({ version: 2, steps: [{ wait: { screen: "x", stable: "1s" } }] })
    end.to raise_error(Shellfie::ValidationError, /one condition/)

    config = described_class.new({
      version: 2,
      terminal: { env: { "REMOVE_ME" => nil } },
      steps: [{ key: "enter", async: true }, { capture: "ready" }],
      outputs: [{ path: "capture.svg", capture: "ready" }]
    })
    expect(config.terminal[:env]).to eq("REMOVE_ME" => nil)
    expect(config.outputs.first[:capture]).to eq("ready")
  end

  it "rejects cyclic aliases, non-symbolizable keys, and unbounded durations" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "session.yml")
      File.write(path, "version: 2\nsteps: &cycle\n  - wait: *cycle\n")
      expect { described_class.parse(path) }.to raise_error(Shellfie::ParseError, /cycles/)
    end

    expect do
      described_class.new({ version: 2, steps: [], terminal: { 1 => "bad" } })
    end.to raise_error(Shellfie::ValidationError, /keys/)
    expect do
      described_class.new({ version: 2, steps: [{ sleep: "#{"9" * 1_000}s" }] })
    end.to raise_error(Shellfie::ValidationError, /finite/)
  end
end
