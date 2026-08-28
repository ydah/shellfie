# frozen_string_literal: true

require "spec_helper"
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
end
