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
end
