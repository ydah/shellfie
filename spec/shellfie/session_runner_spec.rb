# frozen_string_literal: true

require "spec_helper"
require "tempfile"

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

  it "preserves command output that has no trailing newline" do
    config = Shellfie::SessionConfig.new(
      {
        version: 2,
        terminal: { shell: "/bin/sh", columns: 80, rows: 10, timeout: 2 },
        steps: [{ run: "printf UNIQUE", visibility: "visible" }]
      }
    )

    session = described_class.new(config).run

    expect(session.screen.to_s.scan("UNIQUE").size).to eq(2)
  end

  it "replaces invalid terminal bytes instead of timing out" do
    config = Shellfie::SessionConfig.new(
      { version: 2, terminal: { shell: "/bin/sh", timeout: 2 }, steps: [{ run: "printf '\\377'", visibility: "visible" }] }
    )

    expect(described_class.new(config).run.screen.to_s).to include("�")
  end

  it "carries incomplete UTF-8 characters across terminal chunks" do
    runner = described_class.new(Shellfie::SessionConfig.new({ version: 2, steps: [] }))
    bytes = "界".b

    expect(runner.send(:decode_terminal_bytes, bytes.byteslice(0, 2))).to eq("")
    expect(runner.send(:decode_terminal_bytes, bytes.byteslice(2, 1))).to eq("界")
  end

  it "terminates background processes left by the shell" do
    pid_file = Tempfile.new("shellfie-child-pid")
    pid_file.close
    command = "sh -c 'trap \"\" HUP TERM; sleep 30' & echo $! > #{pid_file.path}"
    config = Shellfie::SessionConfig.new(
      { version: 2, terminal: { shell: "/bin/sh", timeout: 2 }, steps: [{ run: command }] }
    )

    runner = described_class.new(config)
    runner.run
    child_pid = Integer(File.read(pid_file.path).strip)

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.5
    begin
      running = runner.send(:process_exists?, child_pid)
      sleep(0.01)
      child_pid = nil unless running
    rescue Errno::ESRCH
      child_pid = nil
    end while child_pid && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    expect(child_pid).to be_nil
  ensure
    begin
      Process.kill("KILL", child_pid) if child_pid
    rescue Errno::ESRCH
      nil
    end
    pid_file&.close!
  end


  it "bounds pathological regular expression evaluation" do
    config = Shellfie::SessionConfig.new({ version: 2, steps: [] })
    runner = described_class.new(config)

    cases = [
      [/(a+)+$/, ("a" * 10_000) + "X"],
      [/(?=(a+))a*b\1/, "a" * 20_000]
    ]
    blocked = cases.any? do |pattern, input|
      runner.send(:regex_match, pattern, input)
      false
    rescue Shellfie::ExecutionError => e
      e.message.include?("Regular expression")
    end

    expect(blocked).to be true
  end
end
