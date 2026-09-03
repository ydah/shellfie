# frozen_string_literal: true

require 'spec_helper'
require 'strscan'

RSpec.describe Shellfie::Terminal::ANSIParser do
  subject(:parser) { described_class.new }

  it 'does not crash on arbitrary terminal bytes' do
    parser = described_class.new
    random = Random.new(54_321)

    100.times { parser.parse(random.bytes(random.rand(0..128))) }
  end

  describe '#parse' do
    it 'parses colon-form truecolor without exposing control text' do
      segments = parser.parse("\e[38:2::255:0:0mX")

      expect(segments.map(&:text).join).to eq('X')
      expect(segments.last.foreground).to eq('#ff0000')
    end

    it 'ignores malformed colon-form colors' do
      expect(parser.parse("\e[38:2:255:0mX").last.foreground).to be_nil
      expect(parser.parse("\e[38:5:1:196mX").last.foreground).to be_nil
    end

    it 'parses plain text without ANSI codes' do
      segments = parser.parse('Hello World')

      expect(segments.size).to eq(1)
      expect(segments.first.text).to eq('Hello World')
      expect(segments.first.foreground).to be_nil
    end

    it 'parses basic colors' do
      segments = parser.parse("\e[31mRed Text\e[0m")

      expect(segments.size).to eq(1)
      expect(segments.first.text).to eq('Red Text')
      expect(segments.first.foreground).to eq(:red)
    end

    it 'parses green text' do
      segments = parser.parse("\e[32mGreen\e[0m")

      expect(segments.first.foreground).to eq(:green)
    end

    it 'parses bold text' do
      segments = parser.parse("\e[1mBold\e[0m")

      expect(segments.first.bold).to be true
    end

    it 'parses italic text' do
      segments = parser.parse("\e[3mItalic\e[0m")

      expect(segments.first.italic).to be true
    end

    it 'parses underlined text' do
      segments = parser.parse("\e[4mUnderline\e[0m")

      expect(segments.first.underline).to be true
    end

    it 'parses multiple segments' do
      segments = parser.parse("\e[31mRed\e[0m Normal \e[32mGreen\e[0m")

      expect(segments.size).to eq(3)
      expect(segments[0].text).to eq('Red')
      expect(segments[0].foreground).to eq(:red)
      expect(segments[1].text).to eq(' Normal ')
      expect(segments[2].text).to eq('Green')
      expect(segments[2].foreground).to eq(:green)
    end

    it 'parses bright colors' do
      segments = parser.parse("\e[91mBright Red\e[0m")

      expect(segments.first.foreground).to eq(:bright_red)
    end

    it 'parses background colors' do
      segments = parser.parse("\e[44mBlue BG\e[0m")

      expect(segments.first.background).to eq(:blue)
    end

    it 'handles 256 colors' do
      segments = parser.parse("\e[38;5;196mColor\e[0m")

      expect(segments.first.foreground).to be_a(String)
      expect(segments.first.foreground).to start_with('#')
    end

    it 'uses xterm 256-color cube values' do
      segments = parser.parse("\e[38;5;17mColor\e[0m")

      expect(segments.first.foreground).to eq('#00005f')
    end

    it 'ignores out-of-range 256 colors' do
      segments = parser.parse("\e[38;5;999mColor\e[0m")

      expect(segments.first.foreground).to be_nil
    end

    it 'handles RGB colors' do
      segments = parser.parse("\e[38;2;255;128;64mRGB\e[0m")

      expect(segments.first.foreground).to eq('#ff8040')
    end

    it 'safely ignores incomplete RGB colors' do
      expect { parser.parse("\e[38;2;255mRGB") }.not_to raise_error
    end

    it 'handles nested styles' do
      segments = parser.parse("\e[1;31mBold Red\e[0m")

      expect(segments.first.bold).to be true
      expect(segments.first.foreground).to eq(:red)
    end

    it 'parses dim reverse strikethrough and overline' do
      segments = parser.parse("\e[2;7;9;53mStyled\e[0m")

      expect(segments.first.dim).to be true
      expect(segments.first.reverse).to be true
      expect(segments.first.strikethrough).to be true
      expect(segments.first.overline).to be true
    end

    it 'parses underline variants, decoration color, blink, and conceal' do
      segments = parser.parse("\e[4:3;58:2::1:2:3;5;8mhidden\e[24;59;25;28mshown")

      expect(segments.first).to have_attributes(
        underline: true, underline_style: :curly, underline_color: '#010203', blink: true, conceal: true
      )
      expect(segments.last).to have_attributes(underline: false, underline_color: nil, blink: false, conceal: false)
      expect(parser.parse("\e[21mdouble").first.underline_style).to eq(:double)
    end

    it 'applies carriage returns and backspaces' do
      expect(parser.parse("old\rnew").first.text).to eq('new')
      expect(parser.parse("abc\bX").first.text).to eq('abX')
      expect(parser.parse("abc\b").first.text).to eq('abc')
    end

    it 'advances tabs to the next configured tab stop' do
      tab_parser = described_class.new(tab_width: 4)

      expect(tab_parser.parse("a\tb").first.text).to eq('a   b')
      expect(tab_parser.parse("abcd\tb").first.text).to eq('abcd    b')
      expect(described_class.new(tab_width: 8).parse("界\tX").first.text).to eq('界      X')
      expect(described_class.new.parse("abcdefghij\r\tX").first.text).to eq('abcdefghXj')
    end

    it 'uses terminal cell width when overwriting wide graphemes' do
      expect(described_class.new.parse("界\bX").first.text).to eq(' X')
    end

    it 'applies simple cursor movement' do
      expect(parser.parse("abc\e[2DX").first.text).to eq('aXc')
      expect(parser.parse("abc\e[1GX").first.text).to eq('Xbc')
    end

    it 'preserves cursor-right gaps as spaces' do
      expect(parser.parse("a\e[3CX").first.text).to eq('a   X')
    end

    it 'handles ANSI clear line controls' do
      expect(parser.parse("abc\e[1G\e[KX").first.text).to eq('X')
      expect(parser.parse("abc\e[2K\e[1GX").first.text).to eq('X')
    end

    it 'handles ANSI clear screen with cursor home' do
      expect(parser.parse("old\e[2J\e[HX").first.text).to eq('X')
      expect(parser.parse("old\e[2J\e[2HX").first.text).to eq('X')
    end

    it 'ignores OSC hyperlinks and terminal bell' do
      segments = parser.parse("\e]8;;https://example.com\aLink\e]8;;\a\a")

      expect(segments.first.text).to eq('Link')
      expect(segments.first.link).to be_nil
    end

    it 'ignores terminal graphics string controls' do
      segments = parser.parse("before\ePqSIXEL\e\\middle\e_Gkitty\e\\after")

      expect(segments.map(&:text).join).to eq('beforemiddleafter')
    end

    it 'can reject unsupported terminal graphics' do
      strict = described_class.new(graphics_policy: 'error')

      expect { strict.parse("\ePqSIXEL\e\\") }.to raise_error(Shellfie::ValidationError, /Terminal graphics/)
      expect { strict.parse("\e_Gkitty\e\\") }.to raise_error(Shellfie::ValidationError, /Terminal graphics/)
      expect do
        strict.parse("\e]1337;File=name=x:AAAA\a")
      end.to raise_error(Shellfie::ValidationError, /Terminal graphics/)
    end

    it 'preserves only safe OSC 8 hyperlinks when enabled' do
      link_parser = described_class.new(osc_policy: 'preserve')
      segments = link_parser.parse("\e]8;;https://example.com?a=1&b=2\aLink\e[0m!\e]8;;\a plain")

      expect(segments[0]).to have_attributes(text: 'Link', link: 'https://example.com?a=1&b=2')
      expect(segments[1]).to have_attributes(text: '!', link: 'https://example.com?a=1&b=2')
      expect(segments[2]).to have_attributes(text: ' plain', link: nil)
      expect(link_parser.parse("\e]8;;javascript:alert(1)\aunsafe").first.link).to be_nil
      expect(link_parser.parse("\e]8;;#{'x' * 2_049}\atoo-long").first.link).to be_nil
    end

    it 'buffers OSC 8 sequences split across input chunks' do
      link_parser = described_class.new(osc_policy: 'preserve')

      expect(link_parser.parse("before\e]8;;https://exam").map(&:text)).to eq(['before'])
      segment = link_parser.parse("ple.com\e\\Link\e]8;;\e\\").first
      expect(segment).to have_attributes(text: 'Link', link: 'https://example.com')
    end

    it 'can reset ANSI state for each line' do
      line_parser = described_class.new(state_mode: :line)

      line_parser.parse("\e[31mRed")
      segments = line_parser.parse('Plain')

      expect(segments.first.foreground).to be_nil
    end
  end
end
