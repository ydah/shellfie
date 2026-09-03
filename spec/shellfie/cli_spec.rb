# frozen_string_literal: true

require 'spec_helper'
require 'shellfie/session/runner'
require 'tmpdir'

RSpec.describe Shellfie::CLI do
  describe '#run' do
    it 'shows help with no arguments' do
      cli = described_class.new([])
      expect { cli.run }.to output(/Shellfie - Deterministic terminal visual compiler/).to_stdout
    end

    it 'shows version' do
      cli = described_class.new(['version'])
      expect { cli.run }.to output(/shellfie #{Shellfie::VERSION}/o).to_stdout
    end

    it 'shows help with --help' do
      cli = described_class.new(['help'])
      expect { cli.run }.to output(/Usage:/).to_stdout
    end

    it 'lists themes' do
      cli = described_class.new(['themes'])
      expect { cli.run }.to output(/macos.*dracula/m).to_stdout
    end

    it 'outputs sample config with init' do
      cli = described_class.new(['init'])
      expect { cli.run }.to output(/theme: macos/).to_stdout
    end

    it 'exits with error for unknown command' do
      cli = described_class.new(['unknown'])
      expect { cli.run }.to output(/Unknown command/).to_stderr.and raise_error(SystemExit)
    end

    it 'does not mutate the provided args array' do
      args = ['version']
      cli = described_class.new(args)

      expect { cli.run }.to output(/shellfie #{Shellfie::VERSION}/o).to_stdout
      expect(args).to eq(['version'])
    end

    it 'rejects invalid scale values' do
      cli = described_class.new(['generate', 'config.yml', '-o', 'out.png', '--scale', '0'])

      expect { cli.run }.to output(/scale must be 1, 2, or 3/).to_stderr.and raise_error(SystemExit)
    end

    it 'warns when the deprecated fps option is used' do
      cli = described_class.new(['generate', 'config.yml', '-o', 'out.gif', '--fps', '30'])
      allow(Shellfie::Parser).to receive(:parse).and_raise(Shellfie::ConfigError, 'stop')

      expect { cli.run }.to output(/--fps is deprecated/).to_stderr.and raise_error(SystemExit)
    end

    it 'keeps explicit WebP output static without frames or --animate' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])
      cli = described_class.new([])
      options = described_class::Options.new(format: 'webp')

      expect(cli.send(:animation_output?, config, options)).to be false
    end

    it 'applies exact aspect presets while allowing an explicit width override' do
      cli = described_class.new([])
      options = described_class::Options.new(preset: 'ogp', width: 1000)

      expect(cli.send(:build_window_overrides, options)).to include(width: 1000, height: 630, exact_size: true)
    end

    it 'derives safe default and templated output names' do
      config = Shellfie::Config.new(theme: 'ubuntu', lines: [Shellfie::Line.new(output: 'ok')])
      cli = described_class.new([])
      options = described_class::Options.new
      expect(cli.send(:output_path_for, 'docs/demo.yml', 'png', multiple: false, config: config,
                                                                options: options, default_output: true))
        .to eq('docs/demo.png')

      options = described_class::Options.new(output: 'build/{name}-{theme}-{scale}.{format}', scale: 2)
      expect(cli.send(:output_path_for, 'docs/demo.yml', 'svg', multiple: false, config: config, options: options))
        .to eq('build/demo-ubuntu-2.svg')
    end

    it 'rejects batch output collisions before rendering' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])
      allow(Shellfie::Parser).to receive(:parse).and_return(config)
      expect(Shellfie::Renderer).not_to receive(:new)

      Dir.mktmpdir('shellfie-cli-spec') do |dir|
        cli = described_class.new(['generate', 'one/same.yml', 'two/same.yml', '-o', "#{dir}/", '--quiet'])
        expect { cli.run }.to output(/same output/).to_stderr.and raise_error(SystemExit)
      end
    end

    it 'rejects a manifest path that would overwrite generated output' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])
      allow(Shellfie::Parser).to receive(:parse).and_return(config)
      expect(Shellfie::Renderer).not_to receive(:new)

      cli = described_class.new(['generate', 'config.yml', '-o', 'out.png', '--manifest', 'out.png', '--force'])

      expect { cli.run }.to output(/Manifest path conflicts/).to_stderr.and raise_error(SystemExit)
    end

    it 'rejects input/output collisions and stdout manifests before rendering' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])
      allow(Shellfie::Parser).to receive(:parse).and_return(config)
      expect(Shellfie::Renderer).not_to receive(:new)

      cli = described_class.new(['generate', 'config.yml', '-o', 'config.yml', '--format', 'png', '--force'])
      expect { cli.run }.to output(/conflicts with an input/).to_stderr.and raise_error(SystemExit)

      cli = described_class.new(['generate', 'config.yml', '-o', '-', '--format', 'png', '--manifest', 'm.json'])
      expect { cli.run }.to output(/manifest cannot/).to_stderr.and raise_error(SystemExit)
    end

    it 'preflights every batch target before rendering any output' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])
      allow(Shellfie::Parser).to receive(:parse).and_return(config)
      expect(Shellfie::Renderer).not_to receive(:new)

      Dir.mktmpdir('shellfie-preflight') do |dir|
        File.write(File.join(dir, 'b.png'), 'old')
        cli = described_class.new(['generate', 'a.yml', 'b.yml', '-o', "#{dir}/", '--quiet'])
        expect { cli.run }.to output(/already exists/).to_stderr.and raise_error(SystemExit)
        expect(File.exist?(File.join(dir, 'a.png'))).to be false
      end
    end

    it 'checks generated output without replacing it' do
      Dir.mktmpdir do |dir|
        input = File.join(dir, 'config.yml')
        output = File.join(dir, 'out.svg')
        File.write(input, "version: 1\nlines:\n  - output: current\n")
        described_class.new(['generate', input, '-o', output, '--format', 'svg', '--no-shadow', '--quiet']).run

        expect do
          described_class.new(['generate', input, '-o', output, '--format', 'svg', '--no-shadow', '--check',
                               '--quiet']).run
        end.not_to raise_error

        File.write(output, 'stale')
        expect do
          described_class.new(['generate', input, '-o', output, '--format', 'svg', '--no-shadow', '--check',
                               '--quiet']).run
        end.to output(/output is stale/).to_stderr.and raise_error(SystemExit)
        expect(File.read(output)).to eq('stale')
      end
    end

    it 'bounds parallel batch rendering after preflight' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])
      allow(Shellfie::Parser).to receive(:parse).and_return(config)
      allow(Shellfie::DependencyChecker).to receive(:ensure_imagemagick!)
      active = maximum = 0
      mutex = Mutex.new

      Dir.mktmpdir do |dir|
        cli = described_class.new(['generate', 'a.yml', 'b.yml', 'c.yml', '-o', "#{dir}/", '--jobs', '2', '--quiet'])
        allow(cli).to receive(:write_rendered_output) do
          mutex.synchronize do
            active += 1
            maximum = [maximum, active].max
          end
          sleep 0.02
          mutex.synchronize { active -= 1 }
        end

        cli.run
      end

      expect(maximum).to eq(2)
      expect { described_class.new(['generate', 'a.yml', '--jobs', '33']).run }
        .to output(/jobs must/).to_stderr.and raise_error(SystemExit)
    end

    it 'rejects an invalid output parent before rendering' do
      Dir.mktmpdir do |dir|
        parent = File.join(dir, 'not-a-directory')
        File.write(parent, 'x')

        options = described_class::Options.new
        expect { described_class.new([]).send(:ensure_output_writable!, File.join(parent, 'out.png'), options) }
          .to raise_error(Shellfie::FileSystemError, /not writable/)
      end
    end

    it 'preserves custom config fields while applying generate overrides' do
      config = Shellfie::Config.new(
        colors: { foreground: '#123456' },
        limits: { max_pixels: 2_000_000 },
        lines: [Shellfie::Line.new(output: 'ok')]
      )
      renderer = instance_double(Shellfie::Renderer, render: 'out.png')
      allow(Shellfie::Parser).to receive(:parse).with('config.yml').and_return(config)
      expect(Shellfie::Renderer).to receive(:new) do |render_config|
        expect(render_config.colors[:foreground]).to eq('#123456')
        expect(render_config.limits[:max_pixels]).to eq(2_000_000)
        expect(render_config.window[:width]).to eq(420)
        renderer
      end

      Dir.mktmpdir('shellfie-cli-spec') do |dir|
        output = File.join(dir, 'out.png')
        cli = described_class.new(['generate', 'config.yml', '-o', output, '--width', '420', '--quiet'])
        cli.run
      end
    end

    it 'renders multiple configured session outputs' do
      session = Shellfie::Session.new(columns: 40, rows: 4)
      session.record('done', visible: true, status: 0)
      cli = described_class.new([])
      options = described_class::Options.new(quiet: true)

      Dir.mktmpdir('shellfie-session-output') do |dir|
        outputs = [
          { path: File.join(dir, 'session.svg'), format: 'svg', scale: 2, shadow: false },
          { path: File.join(dir, 'session.txt'), format: 'txt' }
        ]
        cli.send(:render_session_outputs, session, outputs, base_dir: dir, theme: 'macos', render: {}, options: options)

        expect(File.read(outputs[0][:path])).to include('width="1240"', '>done</text>')
        expect(File.read(outputs[1][:path])).to eq("done\n")
      end
    end

    it 'renders a named session capture' do
      session = Shellfie::Session.new(columns: 40, rows: 4)
      session.record('first')
      session.capture('first')
      session.record("\nsecond")
      cli = described_class.new([])
      options = described_class::Options.new(quiet: true)

      Dir.mktmpdir('shellfie-capture-output') do |dir|
        path = File.join(dir, 'capture.txt')
        cli.send(
          :render_session_outputs,
          session,
          [{ path: path, format: 'txt', capture: 'first' }],
          base_dir: dir,
          theme: 'macos',
          render: {},
          options: options
        )

        expect(File.read(path)).to eq("first\n")
      end
    end

    it 'does not execute replay mode as a live session' do
      cli = described_class.new(['run', 'session.yml', '-o', 'out.txt'])
      config = Shellfie::SessionConfig.new({ version: 2, mode: 'replay', steps: [] })
      allow(Shellfie::SessionConfig).to receive(:parse).and_return(config)

      expect { cli.run }.to output(/use shellfie replay/).to_stderr.and raise_error(SystemExit)
    end

    it 'rejects missing outputs and artifact collisions before executing a session' do
      no_outputs = Shellfie::SessionConfig.new({ version: 2, steps: [{ run: 'touch marker' }] })
      allow(Shellfie::SessionConfig).to receive(:parse).and_return(no_outputs)

      expect { described_class.new(['run', 'session.yml']).run }
        .to output(/Output is required/).to_stderr.and raise_error(SystemExit)

      collision = Shellfie::SessionConfig.new(
        { version: 2, steps: [], outputs: [{ path: 'same.svg', format: 'svg' }] }
      )
      allow(Shellfie::SessionConfig).to receive(:parse).and_return(collision)
      expect do
        described_class.new(['record', 'session.yml', '--cassette', 'same.svg', '--force']).run
      end.to output(/same path/).to_stderr.and raise_error(SystemExit)

      expect do
        described_class.new(['run', 'session.yml', '-o', 'out.png', '--animate']).run
      end.to output(/animated output/).to_stderr.and raise_error(SystemExit)
    end

    it 'records metadata without requiring a rendered output' do
      skip 'Live sessions are unavailable on native Windows' if Gem.win_platform?

      Dir.mktmpdir do |dir|
        config = Shellfie::SessionConfig.new({ version: 2, steps: [] })
        session = Shellfie::Session.new(columns: 80, rows: 24)
        allow(Shellfie::SessionConfig).to receive(:parse).and_return(config)
        allow(Shellfie::SessionRunner).to receive(:new).and_return(instance_double(Shellfie::SessionRunner,
                                                                                   run: session))
        cassette = File.join(dir, 'session.json')

        expect { described_class.new(['record', 'session.yml', '--cassette', cassette]).run }.not_to raise_error
        expect(File).to exist(cassette)
      end
    end

    it 'checks render dependencies before executing session commands' do
      Dir.mktmpdir do |dir|
        output = File.join(dir, 'missing', 'out.mp4')
        config = Shellfie::SessionConfig.new(
          { version: 2, steps: [{ run: 'side effect' }], outputs: [{ path: output, format: 'mp4' }] }
        )
        allow(Shellfie::SessionConfig).to receive(:parse).and_return(config)
        allow(Shellfie::DependencyChecker).to receive(:ensure_imagemagick!)
        allow(Shellfie::DependencyChecker).to receive(:ensure_ffmpeg!).and_raise(Shellfie::DependencyError, 'missing')

        expect { described_class.new(['run', 'session.yml']).run }
          .to output(/missing/).to_stderr.and raise_error(SystemExit)
        expect(Dir.exist?(File.dirname(output))).to be false
      end
    end

    it 'prints doctor checks' do
      allow(Shellfie::DependencyChecker).to receive(:doctor).and_return([
                                                                          { name: 'Ruby', detail: '3.4.0', ok: true }
                                                                        ])
      cli = described_class.new(['doctor'])

      expect { cli.run }.to output(/ok\s+Ruby/).to_stdout
    end

    it 'inspects a config' do
      allow_any_instance_of(described_class).to receive(:configuration_version).and_return(1)
      allow(Shellfie).to receive(:inspect_config).and_return(
        config: { version: 1, title: 'Test', lines: [{}], frames: [] },
        theme: 'macos',
        geometry: { canvas_width: 600, canvas_height: 200 }
      )
      cli = described_class.new(['inspect', 'config.yml'])

      expect { cli.run }.to output(/Estimated size: 600x200/).to_stdout
    end

    it 'inspects a version 2 session' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'session.yml')
        File.write(path, "version: 2\nterminal:\n  columns: 90\n  rows: 12\nsteps: []\n")

        expect { described_class.new(['inspect', '--json', path]).run }
          .to output(/"mode": "run".*"steps": 0/m).to_stdout
      end
    end

    it 'emits JSON, SARIF, and JUnit validation reports' do
      Dir.mktmpdir do |dir|
        valid = File.join(dir, 'valid.yml')
        invalid = File.join(dir, 'invalid.yml')
        File.write(valid, "version: 1\nlines:\n  - output: ok\n")
        File.write(invalid, "version: 1\nwidnow: {}\nlines:\n  - output: ok\n")

        json = capture_stdout { described_class.new(['validate', valid, '--format', 'json']).run }
        expect(JSON.parse(json)).to include('valid' => true, 'path' => valid)

        sarif = capture_stdout do
          expect { described_class.new(['validate', invalid, '--format', 'sarif']).run }.to raise_error(SystemExit)
        end
        sarif_document = JSON.parse(sarif)
        expect(sarif_document).to include('version' => '2.1.0')
        expect(sarif_document.dig('runs', 0, 'results', 0, 'locations', 0, 'physicalLocation', 'artifactLocation',
                                  'uri'))
          .to eq(invalid)

        junit = capture_stdout do
          expect { described_class.new(['validate', invalid, '--format', 'junit']).run }.to raise_error(SystemExit)
        end
        expect(junit).to include('<testsuite name="shellfie validate"', '<failure')
      end
    end
  end

  def capture_stdout
    original = $stdout
    output = StringIO.new
    $stdout = output
    yield
    output.string
  ensure
    $stdout = original
  end
end
