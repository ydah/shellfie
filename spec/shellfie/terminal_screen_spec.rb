# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::TerminalScreen do
  it "treats CRLF as a line break rather than a printable grapheme" do
    screen = described_class.new(columns: 20, rows: 4)

    screen.feed("command\r\noutput")

    expect(screen.lines).to eq(%w[command output])
  end

  it "restores the primary buffer after leaving the alternate screen" do
    screen = described_class.new(columns: 20, rows: 4)
    screen.feed("primary\e[?1049halternate")

    expect(screen.to_s).to eq("alternate")

    screen.feed("\e[?1049l")
    expect(screen.to_s).to eq("primary")
  end

  it "scrolls only inside an active scroll region" do
    screen = described_class.new(columns: 10, rows: 4)
    screen.feed("top\e[2;4r\e[4;1Hbottom\nnext")

    expect(screen.lines.first).to eq("top")
    expect(screen.lines.last).to eq("next")
  end

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
