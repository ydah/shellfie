# frozen_string_literal: true

require "spec_helper"
require "strscan"

RSpec.describe Shellfie::AnsiParser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    it "parses plain text without ANSI codes" do
      segments = parser.parse("Hello World")

      expect(segments.size).to eq(1)
      expect(segments.first.text).to eq("Hello World")
      expect(segments.first.foreground).to be_nil
    end

    it "parses basic colors" do
      segments = parser.parse("\e[31mRed Text\e[0m")

      expect(segments.size).to eq(1)
      expect(segments.first.text).to eq("Red Text")
      expect(segments.first.foreground).to eq(:red)
    end

    it "parses green text" do
      segments = parser.parse("\e[32mGreen\e[0m")

      expect(segments.first.foreground).to eq(:green)
    end

    it "parses bold text" do
      segments = parser.parse("\e[1mBold\e[0m")

      expect(segments.first.bold).to be true
    end

    it "parses italic text" do
      segments = parser.parse("\e[3mItalic\e[0m")

      expect(segments.first.italic).to be true
    end

    it "parses underlined text" do
      segments = parser.parse("\e[4mUnderline\e[0m")

      expect(segments.first.underline).to be true
    end

    it "parses multiple segments" do
      segments = parser.parse("\e[31mRed\e[0m Normal \e[32mGreen\e[0m")

      expect(segments.size).to eq(3)
      expect(segments[0].text).to eq("Red")
      expect(segments[0].foreground).to eq(:red)
      expect(segments[1].text).to eq(" Normal ")
      expect(segments[2].text).to eq("Green")
      expect(segments[2].foreground).to eq(:green)
    end

    it "parses bright colors" do
      segments = parser.parse("\e[91mBright Red\e[0m")

      expect(segments.first.foreground).to eq(:bright_red)
    end

    it "parses background colors" do
      segments = parser.parse("\e[44mBlue BG\e[0m")

      expect(segments.first.background).to eq(:blue)
    end

    it "handles 256 colors" do
      segments = parser.parse("\e[38;5;196mColor\e[0m")

      expect(segments.first.foreground).to be_a(String)
      expect(segments.first.foreground).to start_with("#")
    end

    it "handles RGB colors" do
      segments = parser.parse("\e[38;2;255;128;64mRGB\e[0m")

      expect(segments.first.foreground).to eq("#ff8040")
    end

    it "handles nested styles" do
      segments = parser.parse("\e[1;31mBold Red\e[0m")

      expect(segments.first.bold).to be true
      expect(segments.first.foreground).to eq(:red)
    end
  end
end
