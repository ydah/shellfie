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
end
