# frozen_string_literal: true

require 'spec_helper'
require 'shellfie/animation/ffmpeg_encoder'

RSpec.describe Shellfie::Animation::FFmpegEncoder do
  it 'encodes video at the requested rate and playback speed' do
    status = instance_double(Process::Status, success?: true)
    captured = nil
    allow(Open3).to receive(:capture3) do |*args|
      captured = [args, File.read(args[args.index('-i') + 1])]
      ['', '', status]
    end

    described_class.encode(
      [{ path: '/tmp/frame.png', delay: 1_000 }],
      '/tmp/out.mp4',
      format: 'mp4',
      command: 'ffmpeg',
      framerate: 24,
      playback_speed: 2.0,
      loop: false
    )

    args, concat = captured
    expect(args).to include('-vf', 'fps=24,pad=ceil(iw/2)*2:ceil(ih/2)*2', '-fps_mode', 'cfr', '-t', '0.5')
    expect(concat).to include('duration 0.5')
  end

  it 'encodes APNG as decodable 8-bit frames at the requested rate' do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(['', '', status])

    described_class.encode(
      [{ path: '/tmp/frame.png', delay: 750 }],
      '/tmp/out.apng',
      format: 'apng',
      command: 'ffmpeg',
      framerate: 30,
      playback_speed: 1.5,
      loop: true
    )

    expect(Open3).to have_received(:capture3).with(
      'ffmpeg', '-y', '-f', 'concat', '-safe', '0', '-i', anything,
      '-vf', 'fps=30,format=rgba', '-fps_mode', 'cfr', '-t', '0.5',
      '-plays', '0', '-f', 'apng', '/tmp/out.apng'
    )
  end

  it 'duplicates the APNG tail so concat honors its duration' do
    status = instance_double(Process::Status, success?: true)
    concat = nil
    allow(Open3).to receive(:capture3) do |*args|
      concat = File.read(args[args.index('-i') + 1])
      ['', '', status]
    end

    described_class.encode(
      [{ path: '/tmp/frame.png', delay: 750 }],
      '/tmp/out.apng',
      format: 'apng',
      command: 'ffmpeg',
      framerate: 30,
      playback_speed: 1.0,
      loop: true
    )

    expect(concat.scan(/^file /).size).to eq(2)
  end

  it 'passes APNG loop count and prediction settings as argv' do
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).and_return(['', '', status])

    described_class.encode(
      [{ path: '/tmp/frame.png', delay: 100 }], '/tmp/out.apng',
      format: 'apng', command: 'ffmpeg', framerate: 30, playback_speed: 1.0, loop: false,
      loop_count: 3, apng_prediction: 'mixed'
    )

    expect(Open3).to have_received(:capture3).with(
      'ffmpeg', '-y', '-f', 'concat', '-safe', '0', '-i', anything,
      '-vf', 'fps=30,format=rgba', '-fps_mode', 'cfr', '-t', '0.1',
      '-plays', '3', '-pred', 'mixed', '-f', 'apng', '/tmp/out.apng'
    )
  end

  it 'gives a zero-delay still frame a decodable video duration' do
    status = instance_double(Process::Status, success?: true)
    args = nil
    allow(Open3).to receive(:capture3) { |*value|
      args = value
      ['', '', status]
    }

    described_class.encode(
      [{ path: '/tmp/frame.png', delay: 0 }], '/tmp/out.mp4',
      format: 'mp4', command: 'ffmpeg', framerate: 25, playback_speed: 1.0, loop: false
    )

    expect(args[args.index('-t') + 1].to_f).to be >= 0.04
  end
end
