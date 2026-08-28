# frozen_string_literal: true

require "yaml"
require_relative "errors"

module Shellfie
  class SessionConfig
    ACTIONS = %i[run type key sleep wait expect capture hide show].freeze
    TOP_LEVEL_KEYS = %i[version mode title theme terminal requires steps outputs render redact].freeze
    TERMINAL_KEYS = %i[shell columns rows cwd env timeout prompt].freeze
    OUTPUT_KEYS = %i[path format animate scale shadow transparent].freeze

    attr_reader :path, :mode, :title, :theme, :terminal, :requires, :steps, :outputs, :render, :redactions

    def self.parse(path)
      raw = YAML.safe_load_file(path, symbolize_names: true, aliases: true)
      new(raw, path: File.realpath(path))
    rescue Psych::SyntaxError => e
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
      raise ValidationError, "terminal.cwd must be a string" unless terminal[:cwd].is_a?(String)
      raise ValidationError, "terminal.env must be a mapping" unless terminal[:env].is_a?(Hash)
      unless terminal[:env].all? { |key, value| key.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) && value.is_a?(String) }
        raise ValidationError, "terminal.env keys and values must be strings"
      end
      raise ValidationError, "terminal.timeout must be positive" unless duration(terminal[:timeout]).positive?
      raise ValidationError, "requires must contain command names" unless requires.all? { |item| item.is_a?(String) && item.match?(/\A[\w.+-]+\z/) }

      steps.each_with_index { |step, index| validate_step!(step, index) }
      outputs.each_with_index do |output, index|
        validate_mapping_keys!(output, OUTPUT_KEYS, "outputs[#{index}]")
        raise ValidationError, "outputs[#{index}].path must be a string" unless output[:path].is_a?(String)
      end
      redactions.each { |pattern| Regexp.new(pattern.to_s) }
    rescue RegexpError => e
      raise ValidationError, "Invalid redaction pattern: #{e.message}"
    end

    def validate_step!(step, index)
      actions = step.keys & ACTIONS
      raise ValidationError, "steps[#{index}] must contain exactly one action" unless actions.size == 1

      allowed = actions + %i[visibility timeout speed count]
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
