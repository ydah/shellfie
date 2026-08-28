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

  it "clears both cells when erasing from inside a wide grapheme" do
    screen = described_class.new(columns: 10, rows: 2)

    screen.feed("界\e[2G\e[KX")

    expect(screen.to_s).to eq(" X")
    expect(Shellfie::TextMetrics.cell_width(screen.to_s)).to eq(2)
  end

  it "carries incomplete terminal controls across feed boundaries" do
    screen = described_class.new(columns: 20, rows: 2)

    screen.feed("abc\e[")
    screen.feed("2J")

    expect(screen.to_s).to eq("")
  end

  it "joins grapheme extensions split across feed boundaries" do
    screen = described_class.new(columns: 20, rows: 2)

    screen.feed("e").feed("\u0301")
    screen.feed(" 👨\u200d").feed("👩")

    expect(screen.to_s).to eq("é 👨‍👩")
    expect(Shellfie::TextMetrics.graphemes(screen.to_s)).to eq(["é", " ", "👨‍👩"])
  end

  it "supports saved cursor positions and display clearing" do
    screen = described_class.new(columns: 8, rows: 2)

    screen.feed("old\e[s\e[2J\e[uX")

    expect(screen.to_s).to eq("   X")
  end
end
