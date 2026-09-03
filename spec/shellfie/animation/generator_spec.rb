# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shellfie::Animation::Generator do
  describe 'frame building' do
    it 'uses the configured seed for deterministic jitter' do
      config = Shellfie::Config.new(
        animation: { typing_jitter: 0.5, seed: 42, cursor_blink: false, final_delay: 0 },
        frames: [Shellfie::Frame.new(type: 'abc')]
      )

      first = described_class.new(config).send(:build_animation_frames).map { |frame| frame[:delay] }
      second = described_class.new(config).send(:build_animation_frames).map { |frame| frame[:delay] }
      expect(first).to eq(second)
    end

    it 'builds a single GIF frame from static lines' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'done')])
      generator = described_class.new(config)

      frames = generator.send(:build_animation_frames)

      expect(frames.size).to eq(1)
      expect(frames.first[:lines].first.output).to eq('done')
      expect(frames.first[:delay]).to eq(config.animation[:final_delay])
    end

    it 'uses lines as the initial animation screen' do
      config = Shellfie::Config.new(
        lines: [Shellfie::Line.new(output: 'ready')],
        frames: [Shellfie::Frame.new(prompt: '$ ', type: 'go')]
      )

      first_frame = described_class.new(config).send(:build_animation_frames).first

      expect(first_frame[:lines].first.output).to eq('ready')
    end

    it 'uses a type frame delay instead of the global command delay' do
      config = Shellfie::Config.new(
        animation: { command_delay: 500, cursor_blink: false, final_delay: 0 },
        frames: [Shellfie::Frame.new(prompt: '$ ', type: 'x', delay: 120)]
      )

      delays = described_class.new(config).send(:build_animation_frames).map { |frame| frame[:delay] }

      expect(delays).to include(120)
      expect(delays).not_to include(500)
    end

    it 'types whole grapheme clusters' do
      config = Shellfie::Config.new(
        animation: { final_delay: 0 },
        frames: [Shellfie::Frame.new(prompt: '$ ', type: '👨‍👩‍👧‍👦x')]
      )

      commands = described_class.new(config).send(:build_animation_frames).filter_map do |frame|
        frame[:lines].last&.command
      end

      expect(commands).to include("👨‍👩‍👧‍👦#{described_class.new(config).send(:cursor_text)}")
    end

    it 'adds command pause frames with cursor blinking' do
      config = Shellfie::Config.new(
        animation: { typing_speed: 20, command_delay: 100, cursor_blink: true },
        frames: [Shellfie::Frame.new(prompt: '$ ', type: 'echo ok')]
      )
      generator = described_class.new(config)

      frames = generator.send(:build_animation_frames)

      expect(frames.map { |frame| frame[:delay] }).to include(50)
    end

    it 'rounds animation delays cumulatively without duration drift' do
      config = Shellfie::Config.new(frames: [Shellfie::Frame.new(prompt: '$ ', type: 'x')])
      generator = described_class.new(config)

      delays = generator.send(:animation_delays, [{ delay: 33 }, { delay: 33 }, { delay: 34 }])
      expect(delays).to eq([3, 4, 3])
    end

    it 'drops unrepresentable frames while preserving high-speed duration' do
      config = Shellfie::Config.new(animation: { playback_speed: 100 })
      images = Array.new(32) { |index| { path: index.to_s, delay: index == 31 ? 100 : 200 } }

      entries = described_class.new(config).send(:animation_entries, images)

      expect(entries.sum(&:first)).to eq(6)
      expect(entries.last.last).to equal(images.last)
    end

    it 'uses configured cursor glyphs' do
      config = Shellfie::Config.new(
        cursor: { style: 'bar', color: '#ff0000' },
        frames: [Shellfie::Frame.new(prompt: '$ ', type: 'x')]
      )
      generator = described_class.new(config)

      expect(generator.send(:cursor_text)).to include('|')
      expect(generator.send(:cursor_text)).to include("\e[38;2;255;0;0m")
    end

    it 'preserves semantic prompt and command colors in animation frames' do
      config = Shellfie::Config.new(
        frames: [
          Shellfie::Frame.new(prompt: '$ ', type: 'echo ok', prompt_color: 'green', command_color: '#ff00ff')
        ]
      )
      generator = described_class.new(config)

      command_line = generator.send(:build_animation_frames)
                              .flat_map { |frame| frame[:lines] }
                              .find { |line| line.command == 'echo ok' }

      expect(command_line.prompt_color).to eq('green')
      expect(command_line.command_color).to eq('#ff00ff')
    end

    it 'eases output delays for scrolling output' do
      config = Shellfie::Config.new(
        animation: { output_delay: 100, scroll_easing: 'ease_out', final_delay: 0 },
        frames: [Shellfie::Frame.new(output: "one\ntwo\nthree")]
      )
      generator = described_class.new(config)

      delays = generator.send(:build_animation_frames).map { |frame| frame[:delay] }

      expect(delays.first).to be > delays.last
    end

    it 'adds eased scroll offsets when output exceeds visible lines' do
      config = Shellfie::Config.new(
        window: { visible_lines: 2 },
        animation: { output_delay: 100, scroll_easing: 'ease_out', final_delay: 0 },
        frames: [Shellfie::Frame.new(output: "one\ntwo\nthree")]
      )
      generator = described_class.new(config)

      offsets = generator.send(:build_animation_frames).filter_map { |frame| frame.dig(:window, :scroll_offset) }

      expect(offsets.size).to be > 1
      expect(offsets).to eq(offsets.sort)
      expect(offsets.last).to eq(1.0)
    end

    it 'passes per-frame window overrides into rendered frame configs' do
      config = Shellfie::Config.new(frames: [Shellfie::Frame.new(output: 'one')])
      generator = described_class.new(config)

      frame_config = generator.send(
        :create_frame_config,
        [Shellfie::Line.new(output: 'one')],
        window_overrides: { scroll_offset: 0.5 }
      )

      expect(frame_config.window[:scroll_offset]).to eq(0.5)
    end

    it 'supports reverse, ping-pong, and loop offsets without duplicating endpoints' do
      frames = %w[a b c].map { |text| { lines: [Shellfie::Line.new(output: text)], delay: 10 } }

      reverse = described_class.new(Shellfie::Config.new(frames: [Shellfie::Frame.new(output: 'x')],
                                                         animation: {
                                                           direction: 'reverse', loop_offset: 1
                                                         }))
      expect(reverse.send(:playback_frames, frames).map { |frame| frame[:lines].first.output }).to eq(%w[b a c])

      ping_pong = described_class.new(Shellfie::Config.new(frames: [Shellfie::Frame.new(output: 'x')],
                                                           animation: { direction: 'ping_pong' }))
      expect(ping_pong.send(:playback_frames, frames).map { |frame| frame[:lines].first.output }).to eq(%w[a b c b])
    end

    it 'coalesces identical frames by extending their duration' do
      generator = described_class.new(Shellfie::Config.new)
      lines = [Shellfie::Line.new(output: 'same')]

      frames = generator.send(:coalesce_frames, [{ lines: lines, delay: 10 }, { lines: lines, delay: 20 }])

      expect(frames).to eq([{ lines: lines, delay: 30 }])
    end

    it 'applies a combined type/output frame delay only after its output' do
      config = Shellfie::Config.new(
        animation: { command_delay: 50, output_delay: 10, final_delay: 0, cursor_blink: false },
        frames: [Shellfie::Frame.new(prompt: '$ ', type: 'x', output: 'done', delay: 120)]
      )

      delays = described_class.new(config).send(:build_animation_frames).map { |frame| frame[:delay] }

      expect(delays.count(120)).to eq(1)
      expect(delays).to include(50, 10)
    end

    it 'fixes every rendered frame to the final screen height' do
      config = Shellfie::Config.new(frames: [Shellfie::Frame.new(output: "one\ntwo")])
      generator = described_class.new(config)
      frames = generator.send(:build_animation_frames)

      expect(generator.send(:fixed_visible_lines, frames)).to eq(2)
    end

    it 'writes one PNG per event with a timing manifest' do
      generator = described_class.new(Shellfie::Config.new)

      Dir.mktmpdir('shellfie-sequence-spec') do |dir|
        source = File.join(dir, 'source.png')
        output = File.join(dir, 'frames')
        File.binwrite(source, 'png')

        generator.send(:write_png_sequence, [{ path: source, delay: 250 }], output)

        manifest = JSON.parse(File.read(File.join(output, 'timeline.json')))
        expect(manifest['frames']).to eq([{ 'file' => 'frame_0000.png', 'delay_ms' => 250 }])
        expect(File.binread(File.join(output, 'frame_0000.png'))).to eq('png')
      end
    end

    it 'rejects timelines that would expand beyond the encoded frame limit' do
      config = Shellfie::Config.new(
        animation: { framerate: 120 },
        frames: [Shellfie::Frame.new(output: 'x', delay: 60_000)]
      )
      generator = described_class.new(config)
      frames = generator.send(:build_animation_frames)

      expect do
        generator.send(:validate_workload!, frames, scale: 1, shadow: false)
      end.to raise_error(Shellfie::ResourceLimitError, /timeline/)
    end

    it 'never replaces an unrelated directory with a PNG sequence' do
      generator = described_class.new(Shellfie::Config.new)

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'valuable.txt'), 'keep')
        expect do
          generator.send(:write_png_sequence, [{ path: File.join(dir, 'valuable.txt'), delay: 1 }], dir)
        end.to raise_error(Shellfie::FileSystemError, /non-Shellfie/)
        expect(File.read(File.join(dir, 'valuable.txt'))).to eq('keep')
      end
    end

    it 'removes partial frame output when rendering is interrupted' do
      generator = described_class.new(Shellfie::Config.new)
      Dir.mktmpdir do |parent|
        temp_dir = File.join(parent, 'frames')
        Dir.mkdir(temp_dir)
        allow(Dir).to receive(:mktmpdir).with('shellfie').and_return(temp_dir)
        allow(Shellfie::Renderer).to receive(:new).and_raise(Interrupt)
        frame = { lines: [Shellfie::Line.new(output: 'partial')], delay: 10 }

        expect do
          generator.send(:render_frames, [frame], scale: 1, shadow: false, transparent: false, chrome_cache: nil)
        end.to raise_error(Interrupt)
        expect(Dir.exist?(temp_dir)).to be(false)
      end
    end
  end
end
