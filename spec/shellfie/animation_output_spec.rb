# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "animation output support" do
  it "accepts APNG as an animated CLI format" do
    cli = Shellfie::CLI.new(["generate", "config.yml", "-o", "out.apng", "--format", "apng", "--quiet"])
    config = Shellfie::Config.new(frames: [Shellfie::Frame.new(output: "ok")])
    generator = instance_double(Shellfie::GifGenerator, generate: "out.apng")

    allow(Shellfie::Parser).to receive(:parse).with("config.yml").and_return(config)
    expect(Shellfie::GifGenerator).to receive(:new).and_return(generator)

    cli.run
  end

  it "applies GIF palette settings" do
    config = Shellfie::Config.new(animation: { palette: "theme", dither: false })
    theme = Shellfie::ThemeRegistry.build(config)
    convert = double("MiniMagick::Tool::Convert")

    expect(convert).to receive(:dither).with("None")
    expect(convert).to receive(:colors).with(a_value_between(16, 256))

    Shellfie::GifPalette.new(config: config, theme: theme).apply(convert)
  end

  it "prefixes APNG outputs for ImageMagick" do
    expect(Shellfie::ImageMagickCommandBuilder.output_path("out.apng", format: "apng")).to eq("apng:out.apng")
  end

  it "reuses chrome cache entries for matching geometry" do
    cache = Shellfie::RenderChromeCache.new
    geometry = { canvas_width: 100, canvas_height: 50, scaled_width: 100, scaled_height: 50,
                 scaled_title_bar: 20, margin: 0, shadow: false, scaled_radius: 0 }

    Dir.mktmpdir do
      first = cache.fetch(geometry, transparent: false) { |path| File.write(path, "base") }
      second = cache.fetch(geometry, transparent: false) { |path| File.write(path, "other") }

      expect(second).to eq(first)
      expect(File.read(first)).to eq("base")
      cache.cleanup
      expect(File.exist?(first)).to be false
    end
  end
end
