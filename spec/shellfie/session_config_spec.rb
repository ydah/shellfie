# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

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

    expect do
      described_class.new({ version: 2, steps: [{ type: "x", async: true }] })
    end.to raise_error(Shellfie::ValidationError, /async/)

    expect do
      described_class.new({ version: 2, title: 123, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /title/)
    expect do
      described_class.new({ version: 2, terminal: { prompt: 123 }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /prompt/)
    expect do
      described_class.new({ version: 2, terminal: { prompt: "" }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /blank/)
    expect do
      described_class.new({ version: 2, terminal: { env: { "PS1" => "custom" } }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /PS1/)
    expect do
      described_class.new({ version: 2, steps: [{ wait: { screen: 123 } }] })
    end.to raise_error(Shellfie::ValidationError, /wait\.screen/)
    expect do
      described_class.new({ version: 2, steps: [{ expect: { screen_contains: 123 } }] })
    end.to raise_error(Shellfie::ValidationError, /expect\.screen_contains/)
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

  it "accepts step working directories and text goldens" do
    config = described_class.new({
      version: 2,
      steps: [{ run: "pwd", cwd: "subdir" }, { expect: { golden: "expected.txt" } }]
    })

    expect(config.steps).to include({ run: "pwd", cwd: "subdir" }, { expect: { golden: "expected.txt" } })
  end

  it "loads reusable session scenarios with root policy" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "setup.yml"), "version: 2\nsteps:\n  - run: echo setup\n")
      path = File.join(dir, "session.yml")
      File.write(path, "version: 2\ninclude: setup.yml\ninclude_policy: root\nsteps:\n  - run: echo main\n")

      config = described_class.parse(path)
      expect(config.steps.map { |step| step[:run] }).to eq(["echo setup", "echo main"])
      expect(config.source_paths).to contain_exactly(File.realpath(path), File.realpath(File.join(dir, "setup.yml")))
    end
  end

  it "suggests corrections for misspelled session keys" do
    expect do
      described_class.new({ version: 2, termnal: {}, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /termnal -> terminal/)
  end

  it "rejects included documents that are not mappings" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "invalid.yml"), "- not-a-mapping\n")
      path = File.join(dir, "session.yml")
      File.write(path, "version: 2\ninclude: invalid.yml\nsteps: []\n")

      expect { described_class.parse(path) }.to raise_error(Shellfie::ParseError, /must be a YAML mapping/)
    end
  end

  it "does not let a nested include relax its root policy" do
    Dir.mktmpdir do |dir|
      root = File.join(dir, "root")
      Dir.mkdir(root)
      File.write(File.join(dir, "outside.yml"), "version: 2\nsteps: []\n")
      File.write(File.join(root, "nested.yml"), "version: 2\ninclude: ../outside.yml\ninclude_policy: root\nsteps: []\n")
      path = File.join(root, "session.yml")
      File.write(path, "version: 2\ninclude: nested.yml\nsteps: []\n")

      expect { described_class.parse(path) }.to raise_error(Shellfie::ParseError, /escapes the session root/)
    end
  end

  it "rejects falsey include policies" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "base.yml"), "version: 2\nsteps: []\n")
      path = File.join(dir, "session.yml")
      File.write(path, "version: 2\ninclude: base.yml\ninclude_policy:\nsteps: []\n")

      expect { described_class.parse(path) }.to raise_error(Shellfie::ParseError, /include_policy/)
    end
  end

  it "validates environment allowlists, key delays, and total timeouts" do
    config = described_class.new({
      version: 2,
      terminal: { env: { "CI" => "true" }, env_allowlist: ["CI"], total_timeout: "5s" },
      steps: [{ key: "x", count: 2, delay: "10ms" }, { wait: { prompt: true } },
              { expect: { line: "ok", elapsed_under: "5s" } }]
    })
    expect(config.terminal[:total_timeout]).to eq("5s")

    expect do
      described_class.new({ version: 2, terminal: { env: { "TOKEN" => "x" }, env_allowlist: ["CI"] }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /outside env_allowlist/)
    expect do
      described_class.new({ version: 2, steps: [{ wait: { prompt: false } }] })
    end.to raise_error(Shellfie::ValidationError, /prompt must be true/)
    expect do
      described_class.new({ version: 2, terminal: { env_allowlist: false }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /env_allowlist/)
    expect do
      described_class.new({ version: 2, terminal: { env_allowlist: %w[CI CI] }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /duplicates/)
    expect do
      described_class.new({ version: 2, terminal: { total_timeout: false }, steps: [] })
    end.to raise_error(Shellfie::ValidationError, /duration/)
    expect do
      described_class.new({ version: 2, steps: [{ key: "x", delay: nil }] })
    end.to raise_error(Shellfie::ValidationError, /duration/)
    expect do
      described_class.new({ version: 2, steps: [{ key: "x", count: 501, delay: "1ms" }] })
    end.to raise_error(Shellfie::ValidationError, /too many events/)

    expect do
      described_class.new({ version: 2, steps: Array.new(501) { { run: "true", visibility: "hidden" } } })
    end.not_to raise_error
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


  it "reports exact source locations" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "session.yml")
      File.write(path, "version: 2\nterminal:\n  columns: nope\nsteps: []\n")

      expect { described_class.parse(path) }
        .to raise_error(Shellfie::ValidationError, /session\.yml:3:3: terminal\.columns/)
    end
  end

  it "reports the included source location after array merging" do
    Dir.mktmpdir do |dir|
      included = File.join(dir, "included.yml")
      root = File.join(dir, "session.yml")
      File.write(included, "version: 2\nsteps:\n  - type: echo bad\n    speed: nope\n")
      File.write(root, "version: 2\ninclude: included.yml\nsteps:\n  - run: echo good\n")

      expect { described_class.parse(root) }
        .to raise_error(Shellfie::ValidationError, /included\.yml:4:5: steps\[0\]\.speed/)
    end
  end
end
