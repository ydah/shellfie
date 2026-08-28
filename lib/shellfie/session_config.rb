# frozen_string_literal: true

require "yaml"
require_relative "errors"

module Shellfie
  class SessionConfig
    MAX_BYTES = 1_048_576
    ACTIONS = %i[run type key sleep wait expect capture hide show].freeze
    TOP_LEVEL_KEYS = %i[version mode title theme terminal requires steps outputs render redact].freeze
    TERMINAL_KEYS = %i[shell columns rows cwd env timeout prompt].freeze
    OUTPUT_KEYS = %i[path format animate scale shadow transparent capture].freeze

    attr_reader :path, :mode, :title, :theme, :terminal, :requires, :steps, :outputs, :render, :redactions

    def self.parse(path)
      source_path = File.realpath(path)
      raise ParseError, "Session file is too large: #{path} (max #{MAX_BYTES} bytes)" if File.size(source_path) > MAX_BYTES

      raw = YAML.safe_load(File.read(source_path), symbolize_names: true, aliases: true)
      new(raw, path: source_path)
    rescue Psych::Exception => e
      raise ParseError, "Invalid session YAML syntax: #{e.message}"
    end

    def initialize(raw, path: nil)
      raise ValidationError, "Session configuration must be a YAML mapping" unless raw.is_a?(Hash)

      unknown = raw.keys - TOP_LEVEL_KEYS
      raise ValidationError, "Unknown session key(s): #{unknown.join(", ")}" unless unknown.empty?
      raise ValidationError, "Session config version must be 2" unless raw[:version] == 2

      @path = path
      @mode = (raw[:mode] || "run").to_s
      @title = (raw[:title] || "Terminal Session").to_s
      @theme = (raw[:theme] || "macos").to_s
      @terminal = defaults.merge(symbolize_hash(raw[:terminal] || {}))
      @requires = Array(raw[:requires])
      @steps = Array(raw[:steps]).map { |step| normalize_step(step) }
      @outputs = Array(raw[:outputs]).map { |output| symbolize_hash(output) }
      @render = symbolize_hash(raw[:render] || {})
      @redactions = Array(raw[:redact])
      validate!
    end

    def base_dir
      path ? File.dirname(path) : Dir.pwd
    end

    def to_h
      {
        version: 2,
        mode: mode,
        title: title,
        theme: theme,
        terminal: terminal,
        requires: requires,
        steps: steps,
        outputs: outputs,
        render: render,
        redact: redactions
      }
    end

    private

    def defaults
      {
        shell: ENV.fetch("SHELL", "/bin/sh"),
        columns: 100,
        rows: 28,
        cwd: ".",
        env: {},
        timeout: 30,
        prompt: "$ "
      }
    end

    def symbolize_hash(value)
      raise ValidationError, "Expected a mapping, got #{value.class}" unless value.is_a?(Hash)

      value.each_with_object({}) { |(key, nested), result| result[key.to_sym] = nested }
    end

    def normalize_step(step)
      return { step.to_sym => true } if step.is_a?(String) && %w[hide show].include?(step)

      symbolize_hash(step)
    end

    def validate!
      raise ValidationError, "mode must be run or replay" unless %w[run replay].include?(mode)
      validate_mapping_keys!(terminal, TERMINAL_KEYS, "terminal")
      raise ValidationError, "terminal.shell must be a string" unless terminal[:shell].is_a?(String)
      %i[columns rows].each do |key|
        raise ValidationError, "terminal.#{key} must be a positive integer" unless terminal[key].is_a?(Integer) && terminal[key].positive?
      end
      raise ValidationError, "terminal.columns must be at most 500" if terminal[:columns] > 500
      raise ValidationError, "terminal.rows must be at most 200" if terminal[:rows] > 200
      raise ValidationError, "terminal.cwd must be a string" unless terminal[:cwd].is_a?(String)
      raise ValidationError, "terminal.env must be a mapping" unless terminal[:env].is_a?(Hash)
      unless terminal[:env].all? { |key, value| key.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) && (value.nil? || value.is_a?(String)) }
        raise ValidationError, "terminal.env keys must be names and values must be strings or null"
      end
      raise ValidationError, "terminal.timeout must be positive" unless duration(terminal[:timeout]).positive?
      raise ValidationError, "requires must contain command names" unless requires.all? { |item| item.is_a?(String) && item.match?(/\A[\w.+-]+\z/) }
      raise ValidationError, "Session has too many steps (max 10,000)" if steps.size > 10_000

      steps.each_with_index { |step, index| validate_step!(step, index) }
      capture_names = steps.filter_map { |step| step[:capture] }
      raise ValidationError, "Capture names must be unique" unless capture_names.uniq.size == capture_names.size
      outputs.each_with_index do |output, index|
        validate_mapping_keys!(output, OUTPUT_KEYS, "outputs[#{index}]")
        raise ValidationError, "outputs[#{index}].path must be a string" unless output[:path].is_a?(String)
        if output.key?(:capture) && !output[:capture].is_a?(String)
          raise ValidationError, "outputs[#{index}].capture must be a string"
        end
        if output[:capture] && !capture_names.include?(output[:capture])
          raise ValidationError, "outputs[#{index}] references unknown capture: #{output[:capture]}"
        end
      end
      raise ValidationError, "Too many redaction patterns (max 100)" if redactions.size > 100
      if redactions.any? { |pattern| pattern.to_s.bytesize > 512 }
        raise ValidationError, "Redaction patterns must be at most 512 bytes"
      end
      redactions.each { |pattern| Regexp.new(pattern.to_s) }
    rescue RegexpError => e
      raise ValidationError, "Invalid redaction pattern: #{e.message}"
    end

    def validate_step!(step, index)
      actions = step.keys & ACTIONS
      raise ValidationError, "steps[#{index}] must contain exactly one action" unless actions.size == 1

      allowed = actions + %i[visibility timeout speed count async]
      validate_mapping_keys!(step, allowed, "steps[#{index}]")
      action = actions.first
      value = step[action]
      if %i[run type key capture].include?(action) && !value.is_a?(String)
        raise ValidationError, "steps[#{index}].#{action} must be a string"
      end
      if %i[wait expect].include?(action) && !value.is_a?(Hash) && !value.is_a?(String)
        raise ValidationError, "steps[#{index}].#{action} must be a string or mapping"
      end
      duration(step[:timeout]) if step[:timeout]
      duration(value) if action == :sleep
      if step.key?(:visibility) && !%w[visible hidden].include?(step[:visibility])
        raise ValidationError, "steps[#{index}].visibility must be visible or hidden"
      end
      if step.key?(:count) && (!step[:count].is_a?(Integer) || !step[:count].positive?)
        raise ValidationError, "steps[#{index}].count must be a positive integer"
      end
      if step.key?(:async) && ![true, false].include?(step[:async])
        raise ValidationError, "steps[#{index}].async must be true or false"
      end
      if action == :run && step[:async] && step.fetch(:visibility, "visible") == "hidden"
        raise ValidationError, "steps[#{index}] cannot hide an asynchronous run"
      end
      validate_wait!(value, index) if action == :wait && value.is_a?(Hash)
      validate_expect!(value, index) if action == :expect && value.is_a?(Hash)
    end

    def validate_wait!(value, index)
      condition = symbolize_hash(value)
      validate_mapping_keys!(condition, %i[screen line stable exit timeout], "steps[#{index}].wait")
      predicates = condition.keys & %i[screen line stable exit]
      raise ValidationError, "steps[#{index}].wait must contain one condition" unless predicates.size == 1

      duration(condition[:stable]) if condition[:stable]
      duration(condition[:timeout]) if condition[:timeout]
      if condition.key?(:exit) && condition[:exit] != true
        raise ValidationError, "steps[#{index}].wait.exit must be true"
      end
    end

    def validate_expect!(value, index)
      condition = symbolize_hash(value)
      validate_mapping_keys!(condition, %i[screen_contains screen exit_status cursor_row cursor_column], "steps[#{index}].expect")
      raise ValidationError, "steps[#{index}].expect must contain a condition" if condition.empty?
      if condition.key?(:exit_status) && (!condition[:exit_status].is_a?(Integer) || !condition[:exit_status].between?(0, 255))
        raise ValidationError, "steps[#{index}].expect.exit_status must be between 0 and 255"
      end
      %i[cursor_row cursor_column].each do |key|
        next unless condition.key?(key)
        unless condition[key].is_a?(Integer) && condition[key] >= 0
          raise ValidationError, "steps[#{index}].expect.#{key} must be a non-negative integer"
        end
      end
    end

    def validate_mapping_keys!(hash, allowed, context)
      unknown = hash.keys - allowed
      raise ValidationError, "Unknown #{context} key(s): #{unknown.join(", ")}" unless unknown.empty?
    end

    def duration(value)
      match = /\A(\d+(?:\.\d+)?)(ms|s)?\z/.match(value.to_s)
      raise ValidationError, "Invalid duration: #{value}" unless match

      seconds = match[1].to_f
      seconds /= 1_000 if match[2] == "ms"
      seconds
    end
  end
end
