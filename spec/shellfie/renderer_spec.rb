# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Shellfie::Renderer do
  describe "line preparation" do
    it "preserves trailing output lines" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "one\n")])
      renderer = described_class.new(config)

      lines = renderer.send(:build_lines)

      expect(lines.size).to eq(2)
      expect(lines.first[:segments].first.text).to eq("one")
      expect(lines.last[:segments]).to be_empty
    end

    it "applies semantic prompt and command colors" do
      config = Shellfie::Config.new(
        lines: [
          Shellfie::Line.new(prompt: "$ ", command: "echo test", prompt_color: :green, command_color: "#ff00ff")
        ]
      )
      renderer = described_class.new(config)

      segments = renderer.send(:build_lines).first[:segments]

      expect(segments[0].foreground).to eq(:green)
      expect(segments[1].foreground).to eq("#ff00ff")
    end

    it "wraps long lines when configured" do
      config = Shellfie::Config.new(
        window: { width: 140, padding: 0, overflow: "wrap" },
        font: { size: 20 },
        lines: [Shellfie::Line.new(output: "abcdefghijklmnopqrstuvwxyz")]
      )
      renderer = described_class.new(config)

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: false)

      expect(geometry[:lines].size).to be > 1
    end

    it "clips long lines by default" do
      config = Shellfie::Config.new(
        window: { width: 140, padding: 0 },
        font: { size: 20 },
        lines: [Shellfie::Line.new(output: "abcdefghijklmnopqrstuvwxyz")]
      )
      renderer = described_class.new(config)

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: false)
      text = geometry[:lines].first[:segments].map(&:text).join

      expect(text.length).to be < 26
    end

    it "uses no implicit margin for exact-size output" do
      config = Shellfie::Config.new(
        window: { exact_size: true },
        lines: [Shellfie::Line.new(output: "test")]
      )
      renderer = described_class.new(config)

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: true)

      expect(geometry[:margin]).to eq(0)
      expect(geometry[:canvas_width]).to eq(config.window[:width])
    end

    it "returns logical dimensions separately from scaled canvas size" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "test")])
      renderer = described_class.new(config)

      estimate = renderer.estimate(scale: 2, shadow: false)

      expect(estimate[:scale]).to eq(2)
      expect(estimate[:logical_width]).to eq(config.window[:width])
      expect(estimate[:canvas_width]).to be > estimate[:logical_width]
    end

    it "coalesces adjacent render-ready segments with matching style" do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(prompt: "$ ", command: "echo")])
      renderer = described_class.new(config)

      segments = renderer.send(:build_lines).first[:segments]

      expect(segments.size).to eq(1)
      expect(segments.first.text).to eq("$ echo")
      expect(segments.first).to be_a(Shellfie::RenderSegment)
    end

    it "keeps a hidden scroll buffer line without growing the canvas" do
      lines = %w[one two three].map { |line| Shellfie::Line.new(output: line) }
      config = Shellfie::Config.new(window: { visible_lines: 2, scroll_offset: 0.5 }, lines: lines)
      renderer = described_class.new(config)
      plain = described_class.new(Shellfie::Config.new(window: { visible_lines: 2 }, lines: lines))

      geometry = renderer.send(:build_geometry, renderer.send(:build_lines), scale: 1, shadow: false)
      plain_geometry = plain.send(:build_geometry, plain.send(:build_lines), scale: 1, shadow: false)

      expect(geometry[:lines].size).to eq(3)
      expect(geometry[:visible_line_count]).to eq(2)
      expect(geometry[:logical_height]).to eq(plain_geometry[:logical_height])
      expect(geometry[:scroll_offset]).to eq(0.5)
    end

    it "sanitizes ImageMagick text safely" do
      renderer = described_class.new(Shellfie::Config.new)

      escaped = renderer.send(:escape_text, "it's\\ok\nnow")

      expect(escaped).to eq("it's\\ok now")
    end
  end

  describe "rendering", :integration do
    it "renders a PNG file" do
      skip "ImageMagick is not available" unless Shellfie::DependencyChecker.imagemagick_available?

      Dir.mktmpdir("shellfie-spec") do |dir|
        output = File.join(dir, "terminal.png")
        config = Shellfie::Config.new(
          window: { width: 320, exact_size: true },
          lines: [Shellfie::Line.new(prompt: "$ ", command: "printf 'ok'", output: "\e[32mok\e[0m")]
        )

        described_class.new(config).render(output, shadow: false)

        image = MiniMagick::Image.open(output)
        expect(image.width).to eq(320)
        expect(image.height).to be > 0
        expect(File.size(output)).to be > 0
      end
    end

    it "renders native SVG output with selectable text" do
      Dir.mktmpdir("shellfie-spec") do |dir|
        output = File.join(dir, "terminal.svg")
        config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: "svg")])

        described_class.new(config).render(output, shadow: false, format: "svg")

        svg = File.read(output)
        expect(svg).to include("<svg")
        expect(svg).to include(">svg</text>")
        expect(svg).not_to include("data:image/png;base64,")
        expect(svg).to include("role=\"img\"")
      end
    end

    it "renders a standalone accessible HTML terminal" do
      Dir.mktmpdir("shellfie-spec") do |dir|
        output = File.join(dir, "terminal.html")
        config = Shellfie::Config.new(title: "Demo <terminal>", lines: [Shellfie::Line.new(output: "hello & goodbye")])

        described_class.new(config).render(output, shadow: false, format: "html")

        html = File.read(output)
        expect(html).to include("<!doctype html>", "role=\"img\"", "Demo &lt;terminal&gt;", "hello &amp; goodbye")
      end
    end
  end
end
