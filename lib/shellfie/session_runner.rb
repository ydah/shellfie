# frozen_string_literal: true

require "pty"
require "securerandom"
require "shellwords"
require "timeout"
require_relative "errors"
require_relative "session"
require_relative "text_metrics"

module Shellfie
  class SessionRunner
    KEYS = {
      "enter" => "\r", "tab" => "\t", "esc" => "\e", "escape" => "\e",
      "up" => "\e[A", "down" => "\e[B", "right" => "\e[C", "left" => "\e[D",
      "pageup" => "\e[5~", "pagedown" => "\e[6~", "delete" => "\e[3~", "insert" => "\e[2~"
    }.freeze

    def initialize(config)
      @config = config
      @visible = true
      @redactions = config.redactions.map { |pattern| Regexp.new(pattern.to_s) }
    end

    def run
      check_requirements!
      @session = Session.new(columns: terminal[:columns], rows: terminal[:rows], title: @config.title)
      start_pty
      @config.steps.each { |step| execute(step) }
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
        "TERM" => "xterm-256color", "LANG" => "C.UTF-8", "TZ" => "UTC", "PS1" => "", "HISTFILE" => "/dev/null"
      }.merge(terminal[:env].transform_keys(&:to_s))
      shell = resolve_command(terminal[:shell])
      raise DependencyError, "Shell not found: #{terminal[:shell]}" unless shell
      args = case File.basename(shell)
             when "bash" then %w[--noprofile --norc -i]
             when "zsh" then %w[-f -i]
             else %w[-i]
             end
      cwd = File.expand_path(terminal[:cwd], @config.base_dir)
      @pid = Process.spawn(env, shell, *args, chdir: cwd, in: @slave, out: @slave, err: @slave, pgroup: true)
      @slave.close
      @buffer = +""
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @reader_thread = Thread.new do
        loop do
          chunk = @master.readpartial(4096)
          @mutex.synchronize { @buffer << chunk; @condition.broadcast }
        end
      rescue EOFError, Errno::EIO, IOError
        nil
      end
      wait_for_quiet(0.1)
      clear_buffer
    rescue SystemCallError => e
      raise DependencyError, "Unable to start shell #{terminal[:shell]}: #{e.message}"
    end

    def stop_pty
      return unless @pid

      @master&.write("exit\n") unless @master&.closed?
      Timeout.timeout(1) { Process.wait(@pid) }
    rescue Timeout::Error
      Process.kill("TERM", -@pid)
      Process.wait(@pid)
    rescue Errno::ESRCH, Errno::ECHILD, IOError
      nil
    ensure
      @master&.close unless @master&.closed?
      @reader_thread&.join(0.2)
    end

    def execute(step)
      action = (step.keys & SessionConfig::ACTIONS).first
      case action
      when :hide then @visible = false
      when :show then @visible = true
      when :run then execute_command(step[:run], step, visible: step.fetch(:visibility, "hidden") != "hidden")
      when :type then type(step[:type], step)
      when :key then key(step[:key], step)
      when :sleep then sleep(parse_duration(step[:sleep]))
      when :wait then wait_condition(step[:wait], timeout: step_timeout(step))
      when :expect then expect_condition(step[:expect])
      when :capture then @session.capture(step[:capture])
      end
    end

    def execute_command(command, step, visible:)
      start = buffer_size
      @master.write("#{command}\n")
      text, status = finish_command(start, timeout: step_timeout(step))
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
      typed = buffer_from(start)
      @session.record(redact(typed), delay: delay * TextMetrics.graphemes(text).size, visible: @visible)
    end

    def key(name, step)
      sequence = key_sequence(name)
      start = buffer_size
      count = Integer(step[:count] || 1)
      count.times { @master.write(sequence) }
      if name.downcase == "enter"
        text, status = finish_command(start, timeout: step_timeout(step))
        @session.record(redact(text), delay: 0.1, visible: @visible, status: status)
      else
        wait_for_quiet(0.03)
        @session.record(redact(buffer_from(start)), delay: 0.03, visible: @visible)
      end
    end

    def finish_command(start, timeout:, marker_prefix: "")
      marker = "__SHELLFIE_DONE_#{SecureRandom.hex(8)}__"
      @master.write("#{marker_prefix}printf '\\n#{marker}:%s\\n' \"$?\"\n")
      match = wait_for(/#{Regexp.escape(marker)}:(\d+)/, timeout: timeout, offset: start)
      text = buffer_from(start)[0...match.begin(0)]
      text = text.lines.reject { |line| line.include?(marker) }.join
      [text, match[1].to_i]
    end

    def wait_condition(value, timeout:)
      condition = value.is_a?(Hash) ? value.transform_keys(&:to_sym) : { screen: value }
      pattern = condition[:screen] || condition[:line]
      raise ValidationError, "wait requires screen or line" unless pattern

      wait_for(Regexp.new(pattern.to_s), timeout: parse_duration(condition[:timeout] || timeout), screen: true)
    rescue RegexpError => e
      raise ValidationError, "Invalid wait pattern: #{e.message}"
    end

    def expect_condition(value)
      condition = value.is_a?(Hash) ? value.transform_keys(&:to_sym) : { screen_contains: value }
      current = @session.screen.to_s
      if condition[:screen_contains] && !current.include?(condition[:screen_contains].to_s)
        raise ExecutionError, "Expected screen to contain #{condition[:screen_contains].inspect}"
      end
      if condition[:screen] && !Regexp.new(condition[:screen].to_s).match?(current)
        raise ExecutionError, "Expected screen to match #{condition[:screen].inspect}"
      end
      if condition.key?(:exit_status) && @session.exit_status != condition[:exit_status]
        raise ExecutionError, "Expected exit status #{condition[:exit_status]}, got #{@session.exit_status.inspect}"
      end
    rescue RegexpError => e
      raise ValidationError, "Invalid expect pattern: #{e.message}"
    end

    def wait_for(pattern, timeout:, screen: false, offset: 0)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      loop do
        text = screen ? @session.screen.to_s : buffer_from(offset)
        match = pattern.match(text)
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

    def resolve_command(command)
      return File.expand_path(command) if command.include?(File::SEPARATOR) && File.executable?(File.expand_path(command))

      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
         .map { |path| File.join(path, command) }
         .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
    end

    def key_sequence(name)
      normalized = name.downcase
      return KEYS.fetch(normalized) if KEYS.key?(normalized)
      return (normalized.delete_prefix("ctrl-").ord & 0x1f).chr if normalized.start_with?("ctrl-") && normalized.length == 6

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

      match[2] == "ms" ? match[1].to_f / 1_000 : match[1].to_f
    end

    def redact(text)
      @redactions.reduce(text.to_s) { |result, pattern| result.gsub(pattern, "[REDACTED]") }
    end

    def clear_buffer
      @mutex.synchronize { @buffer.clear }
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
  end
end
