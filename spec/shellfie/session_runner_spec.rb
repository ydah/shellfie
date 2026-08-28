# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::SessionRunner do
  it "types, executes, waits, asserts, captures, and redacts a PTY session" do
    config = Shellfie::SessionConfig.new(
      {
        version: 2,
        terminal: { shell: "/bin/sh", columns: 80, rows: 10, timeout: 5 },
        redact: ["secret"],
        steps: [
          { run: "printf hidden", visibility: "hidden" },
          { type: "printf 'secret-ok'", speed: "1000cps" },
          { key: "enter" },
          { wait: { screen: "REDACTED.*-ok", timeout: "2s" } },
          { expect: { screen_contains: "[REDACTED]-ok", exit_status: 0 } },
          { capture: "done" }
        ]
      }
    )

    session = described_class.new(config).run

    expect(session.screen.to_s).to include("[REDACTED]-ok")
    expect(session.screen.to_s).not_to include("hidden")
    expect(session.captures["done"]).not_to be_empty
  end

  it "waits on live asynchronous output and then collects the exit status" do
    config = Shellfie::SessionConfig.new(
      {
        version: 2,
        terminal: { shell: "/bin/sh", columns: 80, rows: 10, timeout: 5 },
        steps: [
          { type: "printf ready; sleep 0.1; printf done", speed: "1000cps" },
          { key: "enter", async: true },
          { wait: { screen: "ready.*done", timeout: "2s" } },
          { wait: { stable: "50ms", timeout: "2s" } },
          { wait: { exit: true, timeout: "2s" } },
          { expect: { screen_contains: "done", exit_status: 0 } }
        ]
      }
    )

    session = described_class.new(config).run

    expect(session.screen.to_s).to include("ready", "done")
    expect(session.exit_status).to eq(0)
  end

  it "encodes modified character and navigation keys" do
    runner = described_class.new(Shellfie::SessionConfig.new({ version: 2, steps: [] }))

    expect(runner.send(:key_sequence, "ctrl-c")).to eq("\x03")
    expect(runner.send(:key_sequence, "alt-x")).to eq("\ex")
    expect(runner.send(:key_sequence, "ctrl-shift-up")).to eq("\e[1;6A")
  end
end
