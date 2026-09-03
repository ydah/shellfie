# frozen_string_literal: true

require 'spec_helper'
require 'shellfie/session/config'
require 'shellfie/session/runner'
require 'tempfile'

unless Gem.win_platform?
  RSpec.describe Shellfie::Session::Runner do
    it 'types, executes, waits, asserts, captures, and redacts a PTY session' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', columns: 80, rows: 10, timeout: 5 },
          redact: ['secret'],
          steps: [
            { run: 'printf hidden', visibility: 'hidden' },
            { type: "printf 'secret-ok'", speed: '1000cps' },
            { key: 'enter' },
            { wait: { screen: 'REDACTED.*-ok', timeout: '2s' } },
            { expect: { screen_contains: '[REDACTED]-ok', exit_status: 0 } },
            { capture: 'done' }
          ]
        }
      )

      session = described_class.new(config).run

      expect(session.screen.to_s).to include('[REDACTED]-ok')
      expect(session.screen.to_s).not_to include('hidden')
      expect(session.captures['done']).not_to be_empty
    end

    it 'waits on live asynchronous output and then collects the exit status' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', columns: 80, rows: 10, timeout: 5 },
          steps: [
            { type: 'printf ready; sleep 0.1; printf done', speed: '1000cps' },
            { key: 'enter', async: true },
            { wait: { screen: 'ready.*done', timeout: '2s' } },
            { wait: { stable: '50ms', timeout: '2s' } },
            { wait: { exit: true, timeout: '2s' } },
            { expect: { screen_contains: 'done', exit_status: 0 } }
          ]
        }
      )

      session = described_class.new(config).run

      expect(session.screen.to_s).to include('ready', 'done')
      expect(session.exit_status).to eq(0)
    end

    it 'matches line waits and elapsed assertions' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', columns: 80, rows: 10, timeout: 2, total_timeout: 5 },
          steps: [
            { type: "printf 'first\\nsecond\\n'", speed: '1000cps' },
            { key: 'enter', async: true },
            { wait: { line: '^second$', timeout: '2s' } },
            { wait: { exit: true, timeout: '2s' } },
            { expect: { line: '\\Afirst\\z', elapsed_under: '5s' } }
          ]
        }
      )

      expect(described_class.new(config).run.screen.to_s).to include('second')
    end

    it 'waits for the configured shell prompt' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', columns: 80, rows: 10, timeout: 2, prompt: 'READY> ' },
          steps: [
            { type: 'printf done', speed: '1000cps' },
            { key: 'enter', async: true },
            { wait: { prompt: true, timeout: '2s' } },
            { wait: { exit: true, timeout: '2s' } }
          ]
        }
      )

      expect(described_class.new(config).run.screen.to_s).to include('done', 'READY>')
    end

    it 'does not confuse prompt-like program output with a prompt' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2, prompt: '$ ' },
          steps: [
            { type: "printf '$ '; sleep 1", speed: '1000cps' },
            { key: 'enter', async: true },
            { wait: { prompt: true, timeout: '100ms' } }
          ]
        }
      )

      expect { described_class.new(config).run }.to raise_error(Shellfie::ExecutionError, /Timed out/)
    end

    it 'does not confuse an exported prompt marker with prompt completion' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [
            { type: 'env; sleep 1', speed: '1000cps' },
            { key: 'enter', async: true },
            { wait: { prompt: true, timeout: '100ms' } }
          ]
        }
      )

      expect { described_class.new(config).run }.to raise_error(Shellfie::ExecutionError, /Timed out/)
    end

    it 'does not accept a copied prompt while a foreground process is running' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [
            { type: 'printf "$PS1"; sleep 1', speed: '1000cps' },
            { key: 'enter', async: true },
            { wait: { prompt: true, timeout: '100ms' } }
          ]
        }
      )

      expect { described_class.new(config).run }.to raise_error(Shellfie::ExecutionError, /Timed out/)
    end

    it 'sets the configured PTY dimensions' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', rows: 17, columns: 123, timeout: 2 },
          steps: [{ run: 'stty size', visibility: 'visible' }]
        }
      )

      expect(described_class.new(config).run.screen.to_s).to include('17 123')
    end

    it 'records repeated key delays for offline animation' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [{ key: 'enter', count: 3, delay: '20ms', async: true }]
        }
      )

      events = described_class.new(config).run.events
      expect(events.size).to eq(3)
      expect(events.map { |event| event[:delay] }).to eq([0.02, 0.02, 0.03])
    end

    it 'flushes asynchronous output before recording a later key' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [
            { type: 'sleep 0.05; printf LOST', speed: '1000cps' },
            { key: 'enter', async: true },
            { sleep: '100ms' },
            { key: 'x' },
            { key: 'backspace' },
            { wait: { exit: true, timeout: '2s' } }
          ]
        }
      )

      expect(described_class.new(config).run.screen.to_s).to include('LOST')
    end

    it 'flushes asynchronous output before later typing' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [
            { type: 'sleep 0.05; printf LOST', speed: '1000cps' },
            { key: 'enter', async: true },
            { sleep: '100ms' },
            { type: 'x', speed: '1000cps' },
            { key: 'backspace' },
            { wait: { exit: true, timeout: '2s' } }
          ]
        }
      )

      expect(described_class.new(config).run.screen.to_s).to include('LOST')
    end

    it 'keeps no-echo key delays in offline frames' do
      session = Shellfie::Session::Recording.new(
        columns: 20, rows: 2,
        events: [{ text: '', delay: 0.2, visible: true }, { text: 'done', delay: 0.03, visible: true }]
      )

      expect(session.compose_hash['frames'].map { |frame| frame['delay'] }).to eq([200, 30])
    end

    it 'records explicit sleeps as deterministic timeline pauses' do
      config = Shellfie::Session::Config.new(
        { version: 2, terminal: { shell: '/bin/sh', timeout: 2 }, steps: [{ sleep: '20ms' }] }
      )

      expect(described_class.new(config).run.compose_hash['frames'].map { |frame| frame['delay'] }).to eq([20])
    end

    it 'removes its private prompt marker from recorded events' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [{ key: 'enter', async: true }, { wait: { prompt: true, timeout: '1s' } }]
        }
      )

      recorded = described_class.new(config).run.events.map { |event| event[:text] }.join
      expect(recorded).not_to include("\e]9;")
    end

    it 'replaces its private home directory in recorded output' do
      config = Shellfie::Session::Config.new(
        { version: 2, terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [{ run: 'printf "$HOME"', visibility: 'visible' }] }
      )

      recorded = described_class.new(config).run.events.map { |event| event[:text] }.join
      expect(recorded).to include('~')
      expect(recorded).not_to include('shellfie-home')
    end

    it 'encodes modified character and navigation keys' do
      runner = described_class.new(Shellfie::Session::Config.new({ version: 2, steps: [] }))

      expect(runner.send(:key_sequence, 'ctrl-c')).to eq("\x03")
      expect(runner.send(:key_sequence, 'alt-x')).to eq("\ex")
      expect(runner.send(:key_sequence, 'ctrl-shift-up')).to eq("\e[1;6A")
    end

    it 'honors a deleted PATH during requirement checks' do
      config = Shellfie::Session::Config.new({ version: 2, terminal: { env: { 'PATH' => nil } }, requires: ['ruby'],
                                             steps: [] })

      expect { described_class.new(config).run }.to raise_error(Shellfie::DependencyError, /ruby/)
    end

    it 'runs a command in its step working directory and checks a text golden' do
      Dir.mktmpdir do |dir|
        subdir = File.join(dir, 'subdir')
        Dir.mkdir(subdir)
        config = Shellfie::Session::Config.new(
          {
            version: 2,
            terminal: { shell: '/bin/sh', cwd: dir, columns: 200, rows: 10, timeout: 2 },
            steps: [{ run: 'pwd', cwd: 'subdir', visibility: 'visible' }]
          },
          path: File.join(dir, 'session.yml')
        )

        expect(described_class.new(config).run.screen.to_s).to include(subdir)

        File.write(File.join(dir, 'expected.txt'), "expected\n")
        runner = described_class.new(config)
        runner.instance_variable_set(:@session, Shellfie::Session::Recording.new(columns: 20, rows: 2))
        runner.instance_variable_get(:@session).record('expected')
        expect { runner.send(:expect_condition, { golden: 'expected.txt' }) }.not_to raise_error
      end
    end

    it 'rejects working directories outside the session root when configured' do
      Dir.mktmpdir do |dir|
        root = File.join(dir, 'root')
        outside = File.join(dir, 'outside')
        Dir.mkdir(root)
        Dir.mkdir(outside)
        config = Shellfie::Session::Config.new(
          { version: 2, terminal: { cwd: '..', cwd_policy: 'root' }, steps: [] },
          path: File.join(root, 'session.yml')
        )

        expect { described_class.new(config).send(:validate_working_directories!) }
          .to raise_error(Shellfie::FileSystemError, /escapes the session root/)

        File.symlink(outside, File.join(root, 'escape'))
        config = Shellfie::Session::Config.new(
          { version: 2, terminal: { cwd_policy: 'root' }, steps: [{ run: 'pwd', cwd: 'escape' }] },
          path: File.join(root, 'session.yml')
        )
        expect { described_class.new(config).send(:validate_working_directories!) }
          .to raise_error(Shellfie::FileSystemError, /escapes the session root/)
      end
    end

    it 'preserves command output that has no trailing newline' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', columns: 80, rows: 10, timeout: 2 },
          steps: [{ run: 'printf UNIQUE', visibility: 'visible' }]
        }
      )

      session = described_class.new(config).run

      expect(session.screen.to_s.scan('UNIQUE').size).to eq(2)
    end

    it 'replaces invalid terminal bytes instead of timing out' do
      config = Shellfie::Session::Config.new(
        { version: 2, terminal: { shell: '/bin/sh', timeout: 2 },
          steps: [{ run: "printf '\\377'", visibility: 'visible' }] }
      )

      expect(described_class.new(config).run.screen.to_s).to include('�')
    end

    it 'surfaces rejected terminal graphics from the PTY reader' do
      config = Shellfie::Session::Config.new(
        {
          version: 2,
          terminal: { shell: '/bin/sh', timeout: 2 },
          render: { window: { graphics_policy: 'error' } },
          steps: [{ run: "printf '\\033PqSIXEL\\033\\\\'", visibility: 'visible' }]
        }
      )

      expect { described_class.new(config).run }.to raise_error(Shellfie::ValidationError, /Terminal graphics/)
    end

    it 'carries incomplete UTF-8 characters across terminal chunks' do
      runner = described_class.new(Shellfie::Session::Config.new({ version: 2, steps: [] }))
      bytes = '界'.b

      expect(runner.send(:decode_terminal_bytes, bytes.byteslice(0, 2))).to eq('')
      expect(runner.send(:decode_terminal_bytes, bytes.byteslice(2, 1))).to eq('界')
    end

    it 'terminates background processes left by the shell' do
      pid_file = Tempfile.new('shellfie-child-pid')
      pid_file.close
      command = "sh -c 'trap \"\" HUP TERM; sleep 30' & echo $! > #{pid_file.path}"
      config = Shellfie::Session::Config.new(
        { version: 2, terminal: { shell: '/bin/sh', timeout: 2 }, steps: [{ run: command }] }
      )

      runner = described_class.new(config)
      runner.run
      child_pid = Integer(File.read(pid_file.path).strip)

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.5
      while child_pid && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        child_pid = nil unless runner.send(:process_exists?, child_pid)
        sleep(0.01) if child_pid
      end
      expect(child_pid).to be_nil
    ensure
      begin
        Process.kill('KILL', child_pid) if child_pid
      rescue Errno::ESRCH
        nil
      end
      pid_file&.close!
    end

    it 'bounds pathological regular expression evaluation' do
      config = Shellfie::Session::Config.new({ version: 2, steps: [] })
      runner = described_class.new(config)
      pattern = Object.new
      pattern.define_singleton_method(:match) { |_text| sleep(1) }

      expect { runner.send(:regex_match, pattern, 'input') }
        .to raise_error(Shellfie::ExecutionError, /Regular expression/)
    end
  end
end
