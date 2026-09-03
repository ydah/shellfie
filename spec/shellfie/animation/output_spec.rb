# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'shellfie/cli'
require 'shellfie/animation/generator'

RSpec.describe 'animation output support' do
  it 'accepts event-duration PNG sequences as an animated CLI format' do
    expect(Shellfie::CLI::Generate::ANIMATED_FORMATS).to include('png-sequence')
  end

  it 'accepts APNG as an animated CLI format' do
    cli = Shellfie::CLI.new(['generate', 'config.yml', '-o', 'out.apng', '--format', 'apng', '--quiet'])
    config = Shellfie::Config.new(frames: [Shellfie::Frame.new(output: 'ok')])
    generator = instance_double(Shellfie::Animation::Generator, generate: 'out.apng')

    allow(Shellfie::Parser).to receive(:parse).with('config.yml').and_return(config)
    allow(Shellfie::DependencyChecker).to receive(:ensure_imagemagick!)
    allow(Shellfie::DependencyChecker).to receive(:ensure_ffmpeg!)
    expect(Shellfie::Animation::Generator).to receive(:new).and_return(generator)

    cli.run
  end

  it 'applies theme GIF palettes through a remap image' do
    config = Shellfie::Config.new(animation: { palette: 'theme', dither: false })
    theme = Shellfie::Themes::Registry.build(config)
    palette = Shellfie::Animation::GIFPalette.new(config: config, theme: theme)
    convert = double('MiniMagick::Tool::Convert')

    allow(palette).to receive(:build_theme_palette).and_return('theme-palette.png')
    expect(convert).to receive(:dither).with('None')
    expect(convert).to receive(:remap).with('theme-palette.png')
    expect(convert).to receive(:colors).with(a_value_between(16, 256))

    palette.apply(convert)
  ensure
    palette&.cleanup
  end

  it 'builds a global GIF palette from all frames' do
    config = Shellfie::Config.new(animation: { palette: 'global', dither: true })
    theme = Shellfie::Themes::Registry.build(config)
    palette = Shellfie::Animation::GIFPalette.new(config: config, theme: theme)
    convert = double('MiniMagick::Tool::Convert')
    images = [{ path: 'frame-1.png' }, { path: 'frame-2.png' }]

    allow(palette).to receive(:build_global_palette).with(images).and_return('global-palette.png')
    expect(convert).to receive(:dither).with('FloydSteinberg')
    expect(convert).to receive(:remap).with('global-palette.png')
    expect(convert).to receive(:colors).with(256)

    palette.apply(convert, images: images)
  ensure
    palette&.cleanup
  end

  it 'passes GIF color and WebP quality settings to ImageMagick' do
    config = Shellfie::Config.new(
      animation: {
        gif_colors: 32, webp_lossless: false, webp_quality: 72, webp_method: 5, webp_near_lossless: 80
      }
    )
    theme = Shellfie::Themes::Registry.build(config)
    palette = Shellfie::Animation::GIFPalette.new(config: config, theme: theme)
    gif = double('gif')
    allow(palette).to receive(:build_global_palette).and_return(nil)
    expect(gif).to receive(:dither).with('FloydSteinberg')
    expect(gif).to receive(:colors).with(32)
    palette.apply(gif, images: [{ path: 'frame.png' }])

    webp = double('webp')
    expect(webp).to receive(:define).with('webp:lossless=false')
    expect(webp).to receive(:define).with('webp:method=5')
    expect(webp).to receive(:define).with('webp:near-lossless=80')
    expect(webp).to receive(:quality).with(72)
    Shellfie::Animation::Generator.new(config).send(:configure_animation_format, webp, 'webp', images: [], palette: nil)
  ensure
    palette&.cleanup
  end

  it 'prefixes APNG outputs for ImageMagick' do
    expect(Shellfie::Rendering::ImageMagickCommandBuilder.output_path('out.apng', format: 'apng')).to eq('apng:out.apng')
  end

  it 'reuses chrome cache entries for matching geometry' do
    cache = Shellfie::Rendering::ChromeCache.new
    geometry = { canvas_width: 100, canvas_height: 50, scaled_width: 100, scaled_height: 50,
                 scaled_title_bar: 20, margin: 0, shadow: false, scaled_radius: 0 }

    Dir.mktmpdir do
      first = cache.fetch(geometry, transparent: false) { |path| File.write(path, 'base') }
      second = cache.fetch(geometry, transparent: false) { |path| File.write(path, 'other') }

      expect(second).to eq(first)
      expect(File.read(first)).to eq('base')
      cache.cleanup
      expect(File.exist?(first)).to be false
    end
  end
end
