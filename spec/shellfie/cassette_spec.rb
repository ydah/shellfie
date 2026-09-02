# frozen_string_literal: true

require "spec_helper"
require "shellfie/animation/frame_builder"
require "shellfie/session/cassette"
require "tmpdir"

RSpec.describe Shellfie::Cassette do
  it "round-trips captured events without executing them" do
    session = Shellfie::Session.new(columns: 20, rows: 4, title: "Replay")
    session.record("hello", delay: 0.1, visible: true, status: 0)

    Dir.mktmpdir do |dir|
      path = File.join(dir, "session.json")
      described_class.write(path, session)
      replay = described_class.read(path)

      expect(replay.screen.to_s).to eq("hello")
      expect(replay.exit_status).to eq(0)
    end
  end

  it "exports an editable compose configuration" do
    session = Shellfie::Session.new(columns: 20, rows: 4, title: "Recording")
    session.record("hello", delay: 0.25, visible: true)

    expect(session.compose_hash).to include(
      "version" => 1,
      "title" => "Recording",
      "frames" => [{ "screen" => ["hello"], "delay" => 250 }]
    )
  end

  it "never stores hidden terminal content" do
    session = Shellfie::Session.new(columns: 20, rows: 4)
    session.record("TOP_SECRET", visible: false, status: 0)

    expect(JSON.generate(session.to_h)).not_to include("TOP_SECRET")
    expect(session.events.first).to include(text: "", visible: false, status: 0)
  end

  it "rejects malformed event structures" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.json")
      File.write(path, JSON.generate(version: 1, title: "bad", columns: 80, rows: 24, events: ["bad"]))

      expect { described_class.read(path) }.to raise_error(Shellfie::ParseError, /event/)
    end
  end


  it "renders terminal overwrites as screen snapshots and preserves ANSI style" do
    session = Shellfie::Session.new(columns: 20, rows: 4)
    session.record("\e[31mprogress 0%\e[0m\r", delay: 0.1)
    session.record("progress 1%\r", delay: 0.1)

    config = session.render_config(theme: "macos", animated: true)
    frames = Shellfie::AnimationFrameBuilder.new(config).build

    expect(session.screen.to_s).to eq("progress 1%")
    expect(frames.last[:lines].map(&:output)).to eq(["progress 1%"])
    expect(config.frames.first.screen.join).to include("\e[31m")
  end

  it "bounds session snapshots while constructing exports" do
    events = Array.new(501) { { text: "x\r", delay: 0.01, visible: true } }
    session = Shellfie::Session.new(columns: 20, rows: 4, events: events)

    expect { session.render_config(theme: "macos", animated: true) }
      .to raise_error(Shellfie::ResourceLimitError, /session frames/)
    expect { session.compose_hash }.to raise_error(Shellfie::ResourceLimitError, /session frames/)
  end
end
