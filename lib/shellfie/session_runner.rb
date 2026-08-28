# frozen_string_literal: true

require "pty"
require "open3"
require "securerandom"
require "timeout"
require "fileutils"
require "tmpdir"
require "shellwords"
require_relative "errors"
require_relative "session"
require_relative "text_metrics"

module Shellfie
  class SessionRunner
    MAX_OUTPUT_BYTES = 10 * 1_048_576
    REGEXP_TIMEOUT = 0.1
    MAX_GOLDEN_BYTES = 1_048_576
    KEYS = {
      "enter" => "\r", "tab" => "\t", "esc" => "\e", "escape" => "\e",
      "up" => "\e[A", "down" => "\e[B", "right" => "\e[C", "left" => "\e[D",
      "home" => "\e[H", "end" => "\e[F", "pageup" => "\e[5~", "pagedown" => "\e[6~",
      "delete" => "\e[3~", "insert" => "\e[2~", "backspace" => "\x7f", "shift-tab" => "\e[Z"
    }.freeze

    def initialize(config)
      @config = config
      @visible = true
      @redactions = config.redactions.map { |pattern| Regexp.new(pattern.to_s) }
      @utf8_pending = +"".b
    end

    def run
      check_requirements!
      validate_working_directories!
      @session = Session.new(columns: terminal[:columns], rows: terminal[:rows], title: @config.title)
      @live_screen = TerminalScreen.new(columns: terminal[:columns], rows: terminal[:rows])
      start_pty
      @config.steps.each do |step|
        execute(step)
        check_reader_error!
      end
      @session
    ensure
      stop_pty
    end

    private

    def terminal
      @config.terminal
    end

    def start_pty
      @master, @slave = PTY.open
      env = {
        "TERM" => "xterm-256color", "LANG" => "C.UTF-8", "TZ" => "UTC", "PS1" => "", "HISTFILE" => "/dev/null",
        "PATH" => ENV.fetch("PATH", ""), "HOME" => (@session_home = Dir.mktmpdir("shellfie-home")), "TMPDIR" => Dir.tmpdir
      }.merge(terminal[:env].transform_keys(&:to_s))
      shell = resolve_command(terminal[:shell])
      raise DependencyError, "Shell not found: #{terminal[:shell]}" unless shell
      args = case File.basename(shell)
             when "bash" then %w[--noprofile --norc -i]
             when "zsh" then %w[-f -i]
             when "fish" then %w[--no-config -i]
             when "pwsh", "powershell" then %w[-NoLogo -NoProfile -NoExit]
             when "cmd", "cmd.exe" then %w[/Q /K]
             when "nu" then %w[--no-config-file]
             else %w[-i]
             end
      cwd = File.expand_path(terminal[:cwd], @config.base_dir)
      @pid = Process.spawn(
        env, shell, *args, chdir: cwd, in: @slave, out: @slave, err: @slave, pgroup: true, unsetenv_others: true
      )
      @slave.close
      @buffer = +""
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @reader_thread = Thread.new do
        loop do
          append_terminal_chunk(decode_terminal_bytes(@master.readpartial(4096)))
          break if @reader_error
        end
      rescue EOFError, Errno::EIO, IOError
        nil
      ensure
        append_terminal_chunk(decode_terminal_bytes("", final: true))
      end
      wait_for_quiet(0.1)
      clear_buffer
      @recorded_offset = 0
    rescue SystemCallError => e
      raise DependencyError, "Unable to start shell #{terminal[:shell]}: #{e.message}"
    end

    def stop_pty
      return unless @pid

      terminate_job_groups(background_job_pids)
      terminate_descendants
      @master&.write("exit\n") unless @master&.closed?
      Timeout.timeout(1) { Process.wait(@pid) }
    rescue Timeout::Error
      signal_process_group("TERM")
      begin
        Timeout.timeout(1) { Process.wait(@pid) }
      rescue Timeout::Error
        signal_process_group("KILL")
        Process.wait(@pid)
      end
    rescue Errno::ESRCH, Errno::ECHILD, Errno::EIO, Errno::EPIPE, IOError
      nil
    ensure
      signal_process_group("TERM")
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
      sleep(0.01) while process_group_alive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      signal_process_group("KILL") if process_group_alive?
      @master&.close unless @master&.closed?
      @slave&.close unless @slave&.closed?
      @reader_thread&.join(0.2)
      FileUtils.rm_rf(@session_home) if @session_home
    end

    def background_job_pids
      start = buffer_size
      opening = "__SHELLFIE_JOBS_#{SecureRandom.hex(6)}__"
      closing = "__SHELLFIE_JOBS_END_#{SecureRandom.hex(6)}__"
      @master.write("printf '\n#{opening}\n'; jobs -p; printf '#{closing}\n'\n")
      wait_for(/\r?\n#{Regexp.escape(closing)}\r?\n/, timeout: 0.5, offset: start)
      output = buffer_from(start)
      body = output[/\r?\n#{Regexp.escape(opening)}\r?\n(.*?)\r?\n#{Regexp.escape(closing)}\r?\n/m, 1].to_s
      body.lines.filter_map { |line| Integer(line.strip, exception: false) }
    rescue Shellfie::Error, SystemCallError, IOError
      []
    end

    def terminate_job_groups(pids)
      pids.each { |pid| signal_group(pid, "TERM") }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
      sleep(0.01) while pids.any? { |pid| process_group_exists?(pid) } && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      pids.each { |pid| signal_group(pid, "KILL") if process_group_exists?(pid) }
    end

    def terminate_descendants
      pids = descendant_pids
      pids.reverse_each { |pid| signal_process(pid, "TERM") }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 0.2
      sleep(0.01) while pids.any? { |pid| process_exists?(pid) } && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      pids.reverse_each { |pid| signal_process(pid, "KILL") if process_exists?(pid) }
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      sleep(0.01) while pids.any? { |pid| process_exists?(pid) } && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end

    def descendant_pids
      output, status = Open3.capture2("ps", "-eo", "pid=,ppid=")
      return [] unless status.success?

      children = Hash.new { |hash, key| hash[key] = [] }
      output.each_line do |line|
        pid, parent = line.split.map!(&:to_i)
        children[parent] << pid if pid&.positive? && parent&.positive?
      end
      descendants = []
      pending = [@pid]
      until pending.empty?
        found = children[pending.shift]
        descendants.concat(found)
        pending.concat(found)
      end
      descendants
    rescue SystemCallError
      []
    end

    def signal_process(pid, signal)
      Process.kill(signal, pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def signal_group(pid, signal)
      Process.kill(signal, -pid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def process_group_exists?(pid)
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def process_exists?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def execute(step)
      action = (step.keys & SessionConfig::ACTIONS).first
      case action
      when :hide then set_visibility(false)
      when :show then set_visibility(true)
      when :run then execute_command(step[:run], step, visible: step.fetch(:visibility, step[:async] ? "visible" : "hidden") != "hidden")
      when :type then type(step[:type], step)
      when :key then key(step[:key], step)
      when :sleep then sleep(parse_duration(step[:sleep]))
      when :wait
        wait_condition(step[:wait], timeout: step_timeout(step))
        flush_pending
      when :expect then expect_condition(step[:expect])
      when :capture
        flush_pending
        @session.capture(step[:capture])
      end
    end

    def execute_command(command, step, visible:)
      command = "(cd #{Shellwords.escape(step_directory(step[:cwd]))} && #{command})" if step[:cwd]
      start = buffer_size
      @master.write("#{command}\n")
      if step[:async]
        wait_for_quiet(0.03)
        text, @recorded_offset = buffer_snapshot_from(start)
        event = @session.record(redact(text), delay: 0.03, visible: @visible && visible)
        return event
      end

      text, status = finish_command(start, timeout: step_timeout(step))
      @recorded_offset = buffer_size
      @session.record(redact(text), delay: 0.1, visible: @visible && visible, status: status)
    end

    def type(text, step)
      delay = typing_delay(step[:speed])
      start = buffer_size
      TextMetrics.graphemes(text).each do |grapheme|
        @master.write(grapheme)
        sleep(delay) if delay.positive?
      end
      wait_for_quiet(0.03)
      typed, @recorded_offset = buffer_snapshot_from(start)
      @session.record(redact(typed), delay: delay * TextMetrics.graphemes(text).size, visible: @visible)
    end

    def key(name, step)
      sequence = key_sequence(name)
      start = buffer_size
      count = Integer(step[:count] || 1)
      count.times { @master.write(sequence) }
      if name.downcase == "enter" && !step[:async]
        text, status = finish_command(start, timeout: step_timeout(step))
        @recorded_offset = buffer_size
        @session.record(redact(text), delay: 0.1, visible: @visible, status: status)
      else
        wait_for_quiet(0.03)
        text, @recorded_offset = buffer_snapshot_from(start)
        @session.record(redact(text), delay: 0.03, visible: @visible)
      end
    end

    def finish_command(start, timeout:, marker_prefix: "")
      marker = "__SHELLFIE_DONE_#{SecureRandom.hex(8)}__"
      marker_command = "#{marker_prefix}printf '\\n#{marker}:%s\\n' \"$?\""
      @master.write("#{marker_command}\n")
      match = wait_for(/#{Regexp.escape(marker)}:(\d+)/, timeout: timeout, offset: start)
      text = buffer_from(start)[0...match.begin(0)]
      text = text.gsub(marker_command, "")
      [text, match[1].to_i]
    end

    def wait_condition(value, timeout:)
      condition = value.is_a?(Hash) ? value.transform_keys(&:to_sym) : { screen: value }
      return wait_for_exit(timeout: parse_duration(condition[:timeout] || timeout)) if condition[:exit]
      return wait_for_stable(parse_duration(condition[:stable]), timeout: parse_duration(condition[:timeout] || timeout)) if condition[:stable]

      pattern = condition[:screen] || condition[:line]
      raise ValidationError, "wait requires screen or line" unless pattern

      wait_for(Regexp.new(pattern.to_s), timeout: parse_duration(condition[:timeout] || timeout), screen: true)
    rescue RegexpError => e
      raise ValidationError, "Invalid wait pattern: #{e.message}"
    end

    def wait_for_exit(timeout:)
      start = @recorded_offset
      text, status = finish_command(start, timeout: timeout)
      @recorded_offset = buffer_size
      @session.record(redact(text), delay: 0.1, visible: @visible, status: status)
    end

    def wait_for_stable(seconds, timeout:)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      previous = live_screen_text
      stable_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        check_reader_error!
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        current = live_screen_text
        return if current == previous && now - stable_since >= seconds
        raise ExecutionError, "Timed out after #{timeout}s waiting for a stable screen" if now >= deadline

        if current != previous
          previous = current
          stable_since = now
        end
        @mutex.synchronize { @condition.wait(@mutex, [[deadline - now, seconds].min, 0.05].min) }
      end
    end

    def expect_condition(value)
      condition = value.is_a?(Hash) ? value.transform_keys(&:to_sym) : { screen_contains: value }
      current = @session.screen.to_s
      if condition[:screen_contains] && !current.include?(condition[:screen_contains].to_s)
        raise ExecutionError, "Expected screen to contain #{condition[:screen_contains].inspect}"
      end
      if condition[:screen] && !regex_match(Regexp.new(condition[:screen].to_s), current)
        raise ExecutionError, "Expected screen to match #{condition[:screen].inspect}"
      end
      if condition.key?(:exit_status) && @session.exit_status != condition[:exit_status]
        raise ExecutionError, "Expected exit status #{condition[:exit_status]}, got #{@session.exit_status.inspect}"
      end
      if condition[:golden]
        path = File.expand_path(condition[:golden], @config.base_dir)
        expected = File.open(path, "rb") { |file| file.read(MAX_GOLDEN_BYTES + 1) }
        raise ResourceLimitError, "Text golden is too large (max #{MAX_GOLDEN_BYTES} bytes)" if expected.bytesize > MAX_GOLDEN_BYTES
        raise ExecutionError, "Text golden mismatch: #{condition[:golden]}" unless expected == "#{current}\n"
      end
      %i[row column].each do |coordinate|
        expected = condition[:"cursor_#{coordinate}"]
        actual = @session.screen.public_send(coordinate)
        raise ExecutionError, "Expected cursor #{coordinate} #{expected}, got #{actual}" if expected && actual != expected
      end
    rescue RegexpError => e
      raise ValidationError, "Invalid expect pattern: #{e.message}"
    rescue Errno::ENOENT
      raise FileSystemError, "Text golden not found: #{condition[:golden]}"
    end

    def wait_for(pattern, timeout:, screen: false, offset: 0)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        check_reader_error!
        text = screen ? live_screen_text : buffer_from(offset)
        match = regex_match(pattern, text)
        return match if match

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise ExecutionError, "Timed out after #{timeout}s waiting for #{pattern.inspect}" unless remaining.positive?

        @mutex.synchronize { @condition.wait(@mutex, [remaining, 0.05].min) }
      end
    end

    def wait_for_quiet(seconds)
      previous = -1
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + parse_duration(terminal[:timeout])
      loop do
        check_reader_error!
        current = buffer_size
        return if current == previous
        raise ExecutionError, "Terminal did not become idle" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        previous = current
        sleep(seconds)
      end
    end

    def check_requirements!
      missing = @config.requires.reject { |command| resolve_command(command) }
      raise DependencyError, "Required command(s) not found: #{missing.join(", ")}" unless missing.empty?
    end

    def validate_working_directories!
      paths = [File.expand_path(terminal[:cwd], @config.base_dir)]
      paths.concat(@config.steps.filter_map { |step| step_directory(step[:cwd]) if step[:cwd] })
      missing = paths.find { |path| !File.directory?(path) }
      raise FileSystemError, "Working directory not found: #{missing}" if missing
    end

    def step_directory(path)
      File.expand_path(path, File.expand_path(terminal[:cwd], @config.base_dir))
    end

    def decode_terminal_bytes(chunk, final: false)
      bytes = @utf8_pending << chunk.b
      @utf8_pending = final ? +"".b : incomplete_utf8_suffix(bytes)
      complete_size = bytes.bytesize - @utf8_pending.bytesize
      bytes.byteslice(0, complete_size).to_s.force_encoding(Encoding::UTF_8).scrub
    end

    def incomplete_utf8_suffix(bytes)
      (bytes.bytesize - 1).downto([bytes.bytesize - 3, 0].max) do |index|
        byte = bytes.getbyte(index)
        next if byte.between?(0x80, 0xbf)

        expected = if byte.between?(0xc2, 0xdf)
                     2
                   elsif byte.between?(0xe0, 0xef)
                     3
                   elsif byte.between?(0xf0, 0xf4)
                     4
                   end
        suffix = bytes.byteslice(index..)
        return suffix if expected && suffix.bytesize < expected && suffix.bytes.drop(1).all? { |part| part.between?(0x80, 0xbf) }

        break
      end
      +"".b
    end

    def append_terminal_chunk(chunk)
      return if chunk.empty?

      @mutex.synchronize do
        if @buffer.bytesize + chunk.bytesize > MAX_OUTPUT_BYTES
          @reader_error = ResourceLimitError.new("Terminal output exceeded #{MAX_OUTPUT_BYTES} bytes")
        else
          @buffer << chunk
          @live_screen.feed(chunk)
        end
        @condition.broadcast
      end
    end

    def resolve_command(command)
      if command.include?(File::SEPARATOR)
        path = File.expand_path(command, @config.base_dir)
        return path if File.executable?(path)
      end

      env = terminal[:env]
      path = if env.key?("PATH")
               env["PATH"]
             elsif env.key?(:PATH)
               env[:PATH]
             else
               ENV.fetch("PATH", "")
             end
      path.to_s.split(File::PATH_SEPARATOR)
         .map { |path| File.join(path, command) }
         .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
    end

    def key_sequence(name)
      normalized = name.downcase
      return KEYS.fetch(normalized) if KEYS.key?(normalized)

      parts = normalized.split("-")
      base = parts.pop
      modifiers = parts
      raise ValidationError, "Unsupported key: #{name}" unless (modifiers - %w[shift alt ctrl meta]).empty?

      if base.length == 1
        key = modifiers.include?("shift") ? base.upcase : base
        key = (key.ord & 0x1f).chr if modifiers.include?("ctrl")
        key = "\e#{key}" if (modifiers & %w[alt meta]).any?
        return key
      end

      bits = 0
      bits |= 1 if modifiers.include?("shift")
      bits |= 2 if modifiers.include?("alt")
      bits |= 4 if modifiers.include?("ctrl")
      bits |= 8 if modifiers.include?("meta")
      parameter = bits + 1
      suffix = { "up" => "A", "down" => "B", "right" => "C", "left" => "D", "home" => "H", "end" => "F" }[base]
      return "\e[1;#{parameter}#{suffix}" if suffix && bits.positive?

      tilde = { "insert" => 2, "delete" => 3, "pageup" => 5, "pagedown" => 6 }[base]
      return "\e[#{tilde};#{parameter}~" if tilde && bits.positive?

      raise ValidationError, "Unsupported key: #{name}"
    end

    def typing_delay(value)
      rate = value.to_s[/\d+(?:\.\d+)?/]&.to_f || 30.0
      rate = 30.0 unless rate.positive?
      1.0 / rate
    end

    def step_timeout(step)
      parse_duration(step[:timeout] || terminal[:timeout])
    end

    def parse_duration(value)
      match = /\A(\d+(?:\.\d+)?)(ms|s)?\z/.match(value.to_s)
      raise ValidationError, "Invalid duration: #{value}" unless match
      raise ValidationError, "Duration is too large" if match[1].bytesize > 32

      match[2] == "ms" ? match[1].to_f / 1_000 : match[1].to_f
    end

    def redact(text)
      @redactions.reduce(text.to_s) do |result, pattern|
        with_regexp_timeout { result.gsub(pattern, "[REDACTED]") }
      end
    end

    def regex_match(pattern, text)
      with_regexp_timeout { pattern.match(text) }
    end

    def with_regexp_timeout(&block)
      Timeout.timeout(REGEXP_TIMEOUT, &block)
    rescue Timeout::Error
      raise ExecutionError, "Regular expression exceeded #{REGEXP_TIMEOUT}s"
    end

    def live_screen_text
      @mutex.synchronize { redact(@live_screen.to_s) }
    end

    def flush_pending
      text, finish = buffer_snapshot_from(@recorded_offset)
      return if finish <= @recorded_offset

      @session.record(redact(text), delay: 0.03, visible: @visible)
      @recorded_offset = finish
    end

    def set_visibility(visible)
      flush_pending
      @visible = visible
    end

    def clear_buffer
      @mutex.synchronize do
        @buffer.clear
        @live_screen = TerminalScreen.new(columns: terminal[:columns], rows: terminal[:rows])
      end
    end

    def buffer_size
      @mutex.synchronize { @buffer.bytesize }
    end

    def buffer_snapshot
      @mutex.synchronize { @buffer.dup }
    end

    def buffer_from(index)
      @mutex.synchronize { @buffer.byteslice(index..) || "" }
    end

    def buffer_snapshot_from(index)
      @mutex.synchronize { [@buffer.byteslice(index..) || "", @buffer.bytesize] }
    end

    def check_reader_error!
      error = @mutex&.synchronize { @reader_error }
      raise error if error
    end

    def signal_process_group(signal)
      Process.kill(signal, -@pid) if @pid
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    def process_group_alive?
      return false unless @pid

      Process.kill(0, -@pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end
  end
end
