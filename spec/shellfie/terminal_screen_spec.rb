# frozen_string_literal: true

require "spec_helper"
require "shellfie/terminal_screen"

RSpec.describe Shellfie::TerminalScreen do
  it "does not crash on arbitrary terminal bytes" do
    screen = described_class.new(columns: 20, rows: 2)
    random = Random.new(98_765)

    100.times { screen.feed(random.bytes(random.rand(0..128))) }
  end

  it "treats CRLF as a line break rather than a printable grapheme" do
    screen = described_class.new(columns: 20, rows: 4)

    screen.feed("command\r\noutput")

    expect(screen.lines).to eq(%w[command output])
  end

  it "moves across existing cells at a tab stop without erasing them" do
    screen = described_class.new(columns: 20, rows: 2)
    screen.feed("abcdefghij\r\tX")

    expect(screen.to_s).to start_with("abcdefghXj")
  end

  it "preserves extended underline and conceal styles in rendered lines" do
    screen = described_class.new(columns: 20, rows: 2)
    screen.feed("\e[4:3;58:2::1:2:3;5;8msecret")

    segment = Shellfie::AnsiParser.new.parse(screen.render_lines.first).first
    expect(segment).to have_attributes(
      underline_style: :curly, underline_color: "#010203", blink: true, conceal: true
    )
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
    screen.feed("top\e[2;4r\e[4;1Hbottom\r\nnext")

    expect(screen.lines.first).to eq("top")
    expect(screen.lines.last).to eq("next")
  end

  it "does not scroll the screen when line feed is below a restricted scroll region" do
    screen = described_class.new(columns: 4, rows: 5)
    screen.feed("1\r\n2\r\n3\r\n4\r\n5")
    screen.feed("\e[2;4r\e[5;1H\nX")

    expect(screen.lines).to eq(%w[1 2 3 4 X])
  end

  it "applies cursor, erase, insertion, and deletion controls" do
    screen = described_class.new(columns: 8, rows: 3)

    screen.feed("abc\e[2DX\e[1@Y\e[1P")

    expect(screen.to_s).to eq("aXY")
  end

  it "scrolls at the bottom of the screen" do
    screen = described_class.new(columns: 8, rows: 2)

    screen.feed("one\r\ntwo\r\nthree")

    expect(screen.lines).to eq(%w[two three])
  end

  it "tracks wide grapheme cells without splitting them" do
    screen = described_class.new(columns: 4, rows: 2)

    screen.feed("界a\bX")

    expect(screen.to_s).to eq("界X")
  end

  it "defers autowrap until the next printable character" do
    screen = described_class.new(columns: 5, rows: 2)

    screen.feed("abcde\rX")
    expect(screen.lines).to eq(["Xbcde"])

    screen = described_class.new(columns: 5, rows: 2)
    screen.feed("abcdeX")
    expect(screen.lines).to eq(%w[abcde X])
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

  it "discards split terminal graphics without leaking payload text" do
    screen = described_class.new(columns: 20, rows: 2)

    screen.feed("before\ePqSIX").feed("EL\e\\after")
    screen.feed("\e_Gkitty\e\\")

    expect(screen.to_s).to eq("beforeafter")
  end

  it "can reject split terminal graphics" do
    screen = described_class.new(columns: 20, rows: 2, graphics_policy: "error")

    screen.feed("safe\eP0;")
    expect { screen.feed("1qpayload") }.to raise_error(Shellfie::ValidationError, /Terminal graphics/)
  end

  it "bounds incomplete terminal control buffering" do
    screen = described_class.new(columns: 20, rows: 2)
    oversized = "x" * (described_class::MAX_PENDING_CONTROL_BYTES + 1)

    screen.feed("safe\ePq#{oversized}").feed("still payload\e").feed("\\done")

    expect(screen.to_s).to eq("safedone")
  end

  it "bounds incomplete CSI buffering" do
    screen = described_class.new(columns: 20, rows: 2)
    oversized = "1" * (described_class::MAX_PENDING_CONTROL_BYTES + 1)

    screen.feed("safe\e[#{oversized}").feed("2").feed("Jdone")

    expect(screen.to_s).to eq("safedone")
  end

  it "joins grapheme extensions split across feed boundaries" do
    screen = described_class.new(columns: 20, rows: 2)

    screen.feed("e").feed("\u0301")
    screen.feed(" 👨\u200d").feed("👩")

    expect(screen.to_s).to eq("é 👨‍👩")
    expect(Shellfie::TextMetrics.graphemes(screen.to_s)).to eq(["é", " ", "👨‍👩"])
  end

  it "joins split Hangul clusters and preserves the column on line feed" do
    screen = described_class.new(columns: 10, rows: 3)
    screen.feed("ᄀ").feed("ᅡ")
    expect(screen.column).to eq(2)

    screen = described_class.new(columns: 10, rows: 3)
    screen.feed("ab\nX")
    expect(screen.lines).to eq(["ab", "  X"])
  end

  it "keeps line insertion and deletion inside the scroll region" do
    screen = described_class.new(columns: 4, rows: 5)
    screen.feed("1\r\n2\r\n3\r\n4\r\n5")
    screen.feed("\e[2;4r\e[2;1H\e[2L")

    expect(screen.lines.last).to eq("5")
  end

  it "supports saved cursor positions and display clearing" do
    screen = described_class.new(columns: 8, rows: 2)

    screen.feed("old\e[s\e[2J\e[uX")

    expect(screen.to_s).to eq("   X")
  end
end
