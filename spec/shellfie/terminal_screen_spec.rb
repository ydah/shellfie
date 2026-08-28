# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::TerminalScreen do
  it "applies cursor, erase, insertion, and deletion controls" do
    screen = described_class.new(columns: 8, rows: 3)

    screen.feed("abc\e[2DX\e[1@Y\e[1P")

    expect(screen.to_s).to eq("aXY")
  end

  it "scrolls at the bottom of the screen" do
    screen = described_class.new(columns: 8, rows: 2)

    screen.feed("one\ntwo\nthree")

    expect(screen.lines).to eq(%w[two three])
  end

  it "tracks wide grapheme cells without splitting them" do
    screen = described_class.new(columns: 4, rows: 2)

    screen.feed("界a\bX")

    expect(screen.to_s).to eq("界X")
  end

  it "supports saved cursor positions and display clearing" do
    screen = described_class.new(columns: 8, rows: 2)

    screen.feed("old\e[s\e[2J\e[uX")

    expect(screen.to_s).to eq("   X")
  end
end
