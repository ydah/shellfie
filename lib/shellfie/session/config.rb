# frozen_string_literal: true

require 'yaml'
require 'did_you_mean'
require 'rbconfig'
require 'rubygems/requirement'
require_relative '../config'
require_relative '../errors'
require_relative '../parser/validates_input'
require_relative '../yaml_safety'

module Shellfie
  module Session
    class Config
      MAX_BYTES = 1_048_576
      MAX_DURATION = 86_400
      MAX_COUNT = 10_000
      MAX_CAPTURES = 100
      MAX_PATTERN_LENGTH = 512
      MAX_INCLUDE_FILES = 100
      MAX_TOTAL_BYTES = 10 * MAX_BYTES
      ACTIONS = %i[run type key sleep wait expect capture hide show].freeze
      STEP_OPTION_KEYS = {
        run: %i[visibility timeout async cwd], type: %i[speed], key: %i[count async timeout delay],
        sleep: [], wait: %i[timeout], expect: [], capture: [], hide: [], show: []
      }.freeze
      TOP_LEVEL_KEYS = %i[version mode title theme terminal requires steps outputs render redact vars step_sets].freeze
      TERMINAL_KEYS = %i[shell columns rows cwd cwd_policy env env_allowlist timeout total_timeout prompt].freeze
      OUTPUT_KEYS = %i[path format animate scale shadow transparent capture].freeze
      OUTPUT_FORMATS = %w[png gif svg svg-raster webp apng mp4 webm png-sequence html txt ansi json asciicast
                          cast].freeze
      RENDER_KEYS = %i[window font animation headless].freeze

      attr_reader :path, :source_paths, :mode, :title, :theme, :terminal, :requires, :steps, :outputs, :render,
                  :redactions

      def self.parse(path)
        source_path = File.realpath(path)
        raw, documents, provenance = IncludeResolver.call(source_path)
        new(raw, path: source_path, source_paths: documents.map(&:first).uniq)
      rescue ValidationError => e
        raise YAMLSafety.annotate_validation_error(e, documents || [], provenance: provenance || {})
      rescue Psych::Exception => e
        raise ParseError, "Invalid session YAML syntax: #{e.message}"
      rescue Errno::ENOENT
        raise ParseError, "Session file not found: #{path}"
      end

      def initialize(raw, path: nil, source_paths: nil)
        raise ValidationError, 'Session configuration must be a YAML mapping' unless raw.is_a?(Hash)

        unknown = raw.keys - TOP_LEVEL_KEYS
        raise_unknown_keys!(unknown, TOP_LEVEL_KEYS, 'session')
        variables = validate_variables(raw[:vars] || {})
        raw = interpolate_variables(raw.except(:vars), variables)
        raise ValidationError, 'Session config version must be 2' unless raw[:version] == 2
        raise ValidationError, 'Session config must contain steps' unless raw.key?(:steps)
        raise ValidationError, 'Session title must be a string' if raw.key?(:title) && !raw[:title].is_a?(String)

        @path = path
        @source_paths = Array(source_paths || path).compact.freeze
        @mode = (raw[:mode] || 'run').to_s
        @title = (raw[:title] || 'Terminal Session').to_s
        @theme = (raw[:theme] || 'macos').to_s
        @terminal = defaults.merge(symbolize_hash(raw[:terminal] || {}))
        @requires = Array(raw[:requires])
        raise ValidationError, 'steps must be an array' unless raw[:steps].is_a?(Array)

        @steps = expand_steps(raw[:steps], validate_step_sets(raw[:step_sets] || {}))
        @outputs = Array(raw[:outputs]).map { |output| symbolize_hash(output) }
        @render = symbolize_hash(raw[:render] || {})
        %i[window font animation].each do |key|
          @render[key] = symbolize_hash(@render[key]) if @render[key].is_a?(Hash)
        end
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
          shell: ENV.fetch('SHELL', '/bin/sh'),
          columns: 100,
          rows: 28,
          cwd: '.',
          cwd_policy: 'allow',
          env: {},
          env_allowlist: nil,
          timeout: 30,
          total_timeout: nil,
          prompt: '$ '
        }
      end

      def symbolize_hash(value)
        raise ValidationError, "Expected a mapping, got #{value.class}" unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, nested), result|
          raise ValidationError, 'Mapping keys must be strings or symbols' unless key.respond_to?(:to_sym)

          result[key.to_sym] = nested
        end
      end

      def validate_variables(value)
        raise ValidationError, 'vars must be a mapping' unless value.is_a?(Hash)
        raise ValidationError, 'vars may contain at most 100 entries' if value.size > 100

        value.to_h do |name, nested|
          key = name.to_s
          unless key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
            raise ValidationError,
                  'Variable names must use letters, numbers, and underscores'
          end
          unless nested.is_a?(String) || nested.is_a?(Numeric) || [true, false, nil].include?(nested)
            raise ValidationError, "vars.#{key} must be a scalar"
          end
          raise ValidationError, "vars.#{key} is too large" if nested.to_s.bytesize > 4_096

          [key, nested]
        end
      end

      def interpolate_variables(value, variables)
        case value
        when Hash
          value.to_h { |key, nested| [key, interpolate_variables(nested, variables)] }
        when Array
          value.map { |nested| interpolate_variables(nested, variables) }
        when String
          if (match = /\A\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}\z/.match(value))
            return variable_value(match[1], variables)
          end

          value.gsub(/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/) { variable_value(Regexp.last_match(1), variables).to_s }
        else
          value
        end
      end

      def variable_value(name, variables)
        raise ValidationError, "Undefined variable: #{name}" unless variables.key?(name)

        variables[name]
      end

      def validate_step_sets(value)
        raise ValidationError, 'step_sets must be a mapping' unless value.is_a?(Hash)
        raise ValidationError, 'step_sets may contain at most 100 entries' if value.size > 100

        value.to_h do |name, entries|
          key = name.to_s
          unless key.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
            raise ValidationError,
                  'Step set names must use letters, numbers, and underscores'
          end
          raise ValidationError, "step_sets.#{key} must be an array" unless entries.is_a?(Array)

          [key, entries]
        end
      end

      def expand_steps(entries, sets, stack = [])
        entries.each_with_object([]) do |entry, result|
          expanded, repeat = expand_step(entry, sets, stack)
          next unless expanded

          repeat.times { result.concat(Shellfie::Config.deep_dup(expanded)) }
          raise ValidationError, 'Session has too many expanded steps (max 10,000)' if result.size > 10_000
        end
      end

      def expand_step(entry, sets, stack)
        step = normalize_step(entry)
        condition = step.delete(:if)
        return unless condition.nil? || condition_matches?(condition)

        repeat = step.delete(:repeat) || 1
        unless repeat.is_a?(Integer) && repeat.between?(1, MAX_COUNT)
          raise ValidationError, "step repeat must be between 1 and #{MAX_COUNT}"
        end

        [step.key?(:use) ? expand_step_set(step, sets, stack) : [step], repeat]
      end

      def expand_step_set(step, sets, stack)
        raise ValidationError, 'A reusable step may contain only use and repeat' unless step.keys == [:use]

        name = step[:use].to_s
        raise ValidationError, "Unknown step set: #{name}" unless sets.key?(name)
        raise ValidationError, "Circular step set: #{(stack + [name]).join(' -> ')}" if stack.include?(name)

        expand_steps(sets[name], sets, stack + [name])
      end

      def condition_matches?(value)
        condition = symbolize_hash(value)
        validate_mapping_keys!(condition, %i[os shell ruby env], 'step.if')
        raise ValidationError, 'step.if must contain a condition' if condition.empty?

        matches = []
        matches << os_condition_matches?(condition[:os]) if condition.key?(:os)
        matches << shell_condition_matches?(condition[:shell]) if condition.key?(:shell)
        matches << ruby_condition_matches?(condition[:ruby]) if condition.key?(:ruby)
        matches << env_condition_matches?(condition[:env]) if condition.key?(:env)
        matches.all?
      rescue Gem::Requirement::BadRequirementError => e
        raise ValidationError, "Invalid step.if.ruby requirement: #{e.message}"
      end

      def os_condition_matches?(value)
        systems = Array(value).map(&:to_s)
        raise ValidationError, 'step.if.os must be macos, linux, or windows' unless (systems - %w[macos linux
                                                                                                  windows]).empty?

        systems.include?(host_os)
      end

      def shell_condition_matches?(value)
        raise ValidationError, 'step.if.shell must be a string' unless value.is_a?(String)

        File.basename(terminal[:shell]) == value
      end

      def ruby_condition_matches?(value)
        raise ValidationError, 'step.if.ruby must be a requirement string' unless value.is_a?(String)

        Gem::Requirement.new(value).satisfied_by?(Gem::Version.new(RUBY_VERSION))
      end

      def env_condition_matches?(value)
        raise ValidationError, 'step.if.env must be a mapping' unless value.is_a?(Hash)

        configured = terminal[:env].transform_keys(&:to_s)
        value.all? { |name, expected| configured[name.to_s] == expected }
      end

      def host_os
        value = RbConfig::CONFIG['host_os']
        return 'windows' if value.match?(/mswin|mingw|cygwin/)
        return 'macos' if value.include?('darwin')

        'linux'
      end

      def normalize_step(step)
        return { step.to_sym => true } if step.is_a?(String) && %w[hide show].include?(step)

        symbolize_hash(step)
      end

      def validate!
        raise ValidationError, 'mode must be run or replay' unless %w[run replay].include?(mode)

        validate_terminal!
        validate_requirements!
        validate_steps!
        capture_names = validate_captures!
        validate_outputs!(capture_names)
        validate_redactions!
        validate_render!
      end

      def validate_terminal!
        validate_mapping_keys!(terminal, TERMINAL_KEYS, 'terminal')
        raise ValidationError, 'terminal.shell must be a string' unless terminal[:shell].is_a?(String)

        validate_terminal_dimensions!
        raise ValidationError, 'terminal.cwd must be a string' unless terminal[:cwd].is_a?(String)
        raise ValidationError, 'terminal.cwd_policy must be allow or root' unless %w[allow
                                                                                     root].include?(terminal[:cwd_policy])
        raise ValidationError, 'terminal.prompt must be a string' unless terminal[:prompt].is_a?(String)
        raise ValidationError, 'terminal.prompt must not be blank' if terminal[:prompt].strip.empty?

        validate_terminal_environment!
        raise ValidationError, 'terminal.timeout must be positive' unless duration(terminal[:timeout]).positive?

        duration(terminal[:total_timeout]) unless terminal[:total_timeout].nil?
      end

      def validate_terminal_dimensions!
        %i[columns rows].each do |key|
          unless terminal[key].is_a?(Integer) && terminal[key].positive?
            raise ValidationError, "terminal.#{key} must be a positive integer"
          end
        end
        raise ValidationError, 'terminal.columns must be at most 500' if terminal[:columns] > 500
        raise ValidationError, 'terminal.rows must be at most 200' if terminal[:rows] > 200
      end

      def validate_terminal_environment!
        raise ValidationError, 'terminal.env must be a mapping' unless terminal[:env].is_a?(Hash)
        unless terminal[:env].all? do |key, value|
          key.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/) && (value.nil? || value.is_a?(String))
        end
          raise ValidationError, 'terminal.env keys must be names and values must be strings or null'
        end
        raise ValidationError, 'terminal.env.PS1 is managed by terminal.prompt' if terminal[:env].keys.any? do |key|
          key.to_s == 'PS1'
        end

        validate_environment_allowlist! unless terminal[:env_allowlist].nil?
      end

      def validate_environment_allowlist!
        unless terminal[:env_allowlist].is_a?(Array) && terminal[:env_allowlist].all? do |name|
          name.is_a?(String) && name.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
        end
          raise ValidationError, 'terminal.env_allowlist must contain environment variable names'
        end
        unless terminal[:env_allowlist].uniq.size == terminal[:env_allowlist].size
          raise ValidationError, 'terminal.env_allowlist must not contain duplicates'
        end

        disallowed = terminal[:env].keys.map(&:to_s) - terminal[:env_allowlist]
        unless disallowed.empty?
          raise ValidationError, "terminal.env contains variables outside env_allowlist: #{disallowed.join(', ')}"
        end
      end

      def validate_requirements!
        raise ValidationError, 'requires must contain command names' unless requires.all? do |item|
          item.is_a?(String) && item.match?(/\A[\w.+-]+\z/)
        end
      end

      def validate_steps!
        raise ValidationError, 'Session has too many steps (max 10,000)' if steps.size > 10_000

        steps.each_with_index { |step, index| validate_step!(step, index) }
        max_events = Shellfie::Config::DEFAULTS[:limits][:max_frames]
        if expanded_event_count > max_events
          raise ValidationError, "Session expands to too many events (max #{max_events})"
        end
      end

      def expanded_event_count
        steps.sum do |step|
          action = (step.keys & ACTIONS).first
          case action
          when :run
            if step.fetch(:visibility, step[:async] ? 'visible' : 'hidden') == 'visible'
              1
            else
              0
            end
          when :type then 1
          when :key then step[:delay] ? Integer(step[:count] || 1) : 1
          when :wait then step[:wait].is_a?(Hash) && (step[:wait][:exit] || step[:wait]['exit']) ? 1 : 0
          else 0
          end
        end
      end

      def validate_captures!
        capture_names = steps.filter_map { |step| step[:capture] }
        raise ValidationError, "Too many captures (max #{MAX_CAPTURES})" if capture_names.size > MAX_CAPTURES
        raise ValidationError, 'Capture names must be unique' unless capture_names.uniq.size == capture_names.size

        capture_names
      end

      def validate_outputs!(capture_names)
        outputs.each_with_index do |output, index|
          validate_output!(output, index, capture_names)
        end
      end

      def validate_output!(output, index, capture_names)
        validate_mapping_keys!(output, OUTPUT_KEYS, "outputs[#{index}]")
        raise ValidationError, "outputs[#{index}].path must be a string" unless output[:path].is_a?(String)
        if output.key?(:capture) && !output[:capture].is_a?(String)
          raise ValidationError, "outputs[#{index}].capture must be a string"
        end
        if output[:capture] && !capture_names.include?(output[:capture])
          raise ValidationError, "outputs[#{index}] references unknown capture: #{output[:capture]}"
        end
        if output[:format] && !OUTPUT_FORMATS.include?(output[:format].to_s)
          raise ValidationError, "outputs[#{index}].format is unsupported"
        end
        if output[:scale] && (!output[:scale].is_a?(Integer) || !output[:scale].between?(1, 3))
          raise ValidationError, "outputs[#{index}].scale must be between 1 and 3"
        end

        %i[animate shadow transparent].each do |key|
          if output.key?(key) && ![true, false].include?(output[key])
            raise ValidationError, "outputs[#{index}].#{key} must be true or false"
          end
        end
      end

      def validate_redactions!
        raise ValidationError, 'Too many redaction patterns (max 100)' if redactions.size > 100
        if redactions.any? { |pattern| pattern.to_s.length > MAX_PATTERN_LENGTH }
          raise ValidationError, "Redaction patterns must be at most #{MAX_PATTERN_LENGTH} characters"
        end
        raise ValidationError, 'Redaction patterns must be strings' unless redactions.all?(String)

        redactions.each { |pattern| Regexp.new(pattern) }
      rescue RegexpError => e
        raise ValidationError, "Invalid redaction pattern: #{e.message}"
      end

      def validate_render!
        validate_mapping_keys!(render, RENDER_KEYS, 'render')
        %i[window font animation].each do |key|
          raise ValidationError, "render.#{key} must be a mapping" if render.key?(key) && !render[key].is_a?(Hash)
        end
        {
          window: Parser::ValidatesInput::WINDOW_KEYS,
          font: Parser::ValidatesInput::FONT_KEYS,
          animation: Parser::ValidatesInput::ANIMATION_KEYS
        }.each do |key, allowed|
          validate_mapping_keys!(render[key], allowed, "render.#{key}") if render[key]
        end
        if render.key?(:headless) && ![true, false].include?(render[:headless])
          raise ValidationError, 'render.headless must be true or false'
        end

        Shellfie::Config.new(
          theme: theme,
          window: render[:window] || {},
          font: render[:font] || {},
          animation: render[:animation] || {},
          headless: render.fetch(:headless, false)
        )
      end

      def validate_step!(step, index)
        action = step_action(step, index)
        allowed = [action] + STEP_OPTION_KEYS.fetch(action)
        validate_mapping_keys!(step, allowed, "steps[#{index}]")
        value = step[action]
        validate_step_action_value!(action, value, index)
        validate_step_options!(step, action, value, index)
        validate_wait!(value, index) if action == :wait && value.is_a?(Hash)
        validate_pattern_size!(value, "steps[#{index}].wait") if action == :wait && value.is_a?(String)
        validate_expect!(value, index) if action == :expect && value.is_a?(Hash)
      end

      def step_action(step, index)
        actions = step.keys & ACTIONS
        raise ValidationError, "steps[#{index}] must contain exactly one action" unless actions.size == 1

        actions.first
      end

      def validate_step_action_value!(action, value, index)
        if %i[run type key capture].include?(action) && !value.is_a?(String)
          raise ValidationError, "steps[#{index}].#{action} must be a string"
        end
        if %i[wait expect].include?(action) && !value.is_a?(Hash) && !value.is_a?(String)
          raise ValidationError, "steps[#{index}].#{action} must be a string or mapping"
        end
        if %i[hide show].include?(action) && value != true
          raise ValidationError, "steps[#{index}].#{action} must be true"
        end
      end

      def validate_step_options!(step, action, value, index)
        duration(step[:timeout]) if step.key?(:timeout)
        duration(step[:delay]) if step.key?(:delay)
        duration(value) if action == :sleep
        if step.key?(:visibility) && !%w[visible hidden].include?(step[:visibility])
          raise ValidationError, "steps[#{index}].visibility must be visible or hidden"
        end
        if step.key?(:count) && (!step[:count].is_a?(Integer) || !step[:count].between?(1, MAX_COUNT))
          raise ValidationError, "steps[#{index}].count must be between 1 and #{MAX_COUNT}"
        end
        if step.key?(:async) && ![true, false].include?(step[:async])
          raise ValidationError, "steps[#{index}].async must be true or false"
        end
        raise ValidationError, "steps[#{index}].cwd must be a string" if step.key?(:cwd) && !step[:cwd].is_a?(String)
        if action == :run && step[:async] && step.fetch(:visibility, 'visible') == 'hidden'
          raise ValidationError, "steps[#{index}] cannot hide an asynchronous run"
        end

        validate_step_speed!(step[:speed], index) if step.key?(:speed)
      end

      def validate_step_speed!(value, index)
        text = value.to_s
        speed = /\A(\d+(?:\.\d+)?)cps\z/.match(text)&.[](1)&.to_f if text.bytesize <= 32
        return if speed&.between?(1, 1_000)

        raise ValidationError, "steps[#{index}].speed must be between 1cps and 1000cps"
      end

      def validate_wait!(value, index)
        condition = symbolize_hash(value)
        validate_mapping_keys!(condition, %i[screen line prompt stable exit timeout], "steps[#{index}].wait")
        predicates = condition.keys & %i[screen line prompt stable exit]
        raise ValidationError, "steps[#{index}].wait must contain one condition" unless predicates.size == 1

        duration(condition[:stable]) if condition.key?(:stable)
        duration(condition[:timeout]) if condition.key?(:timeout)
        validate_wait_flags!(condition, index)
        validate_wait_patterns!(condition, index)
      end

      def validate_wait_flags!(condition, index)
        %i[exit prompt].each do |key|
          next unless condition.key?(key) && condition[key] != true

          raise ValidationError, "steps[#{index}].wait.#{key} must be true"
        end
      end

      def validate_wait_patterns!(condition, index)
        context = "steps[#{index}].wait"
        validate_pattern_size!(condition[:screen] || condition[:line], context)
        %i[screen line].each do |key|
          raise ValidationError,
                "#{context}.#{key} must be a string" if condition.key?(key) && !condition[key].is_a?(String)
        end
      end

      def validate_expect!(value, index)
        condition = symbolize_hash(value)
        validate_mapping_keys!(condition,
                               %i[screen_contains screen line exit_status cursor_row cursor_column golden elapsed_under elapsed_over], "steps[#{index}].expect")
        raise ValidationError, "steps[#{index}].expect must contain a condition" if condition.empty?

        validate_expected_exit_status!(condition, index)
        validate_expected_cursor!(condition, index)
        validate_expected_text!(condition, index)
        %i[elapsed_under elapsed_over].each { |key| duration(condition[key]) if condition.key?(key) }
      end

      def validate_expected_exit_status!(condition, index)
        if condition.key?(:exit_status) && (!condition[:exit_status].is_a?(Integer) || !condition[:exit_status].between?(
          0, 255
        ))
          raise ValidationError, "steps[#{index}].expect.exit_status must be between 0 and 255"
        end
      end

      def validate_expected_cursor!(condition, index)
        %i[cursor_row cursor_column].each do |key|
          next unless condition.key?(key)
          unless condition[key].is_a?(Integer) && condition[key] >= 0
            raise ValidationError, "steps[#{index}].expect.#{key} must be a non-negative integer"
          end
        end
      end

      def validate_expected_text!(condition, index)
        context = "steps[#{index}].expect"
        validate_pattern_size!(condition[:screen], "steps[#{index}].expect")
        validate_pattern_size!(condition[:line], "steps[#{index}].expect")
        %i[screen line screen_contains].each do |key|
          if condition.key?(key) && !condition[key].is_a?(String)
            raise ValidationError, "#{context}.#{key} must be a string"
          end
        end
        if condition.key?(:golden) && !condition[:golden].is_a?(String)
          raise ValidationError, "#{context}.golden must be a string"
        end
      end

      def validate_mapping_keys!(hash, allowed, context)
        unknown = hash.keys - allowed
        raise_unknown_keys!(unknown, allowed, context)
      end

      def raise_unknown_keys!(unknown, allowed, context)
        return if unknown.empty?

        suggestions = unknown.filter_map do |key|
          match = DidYouMean::SpellChecker.new(dictionary: allowed.map(&:to_s)).correct(key.to_s).first
          "#{key} -> #{match}" if match
        end
        hint = suggestions.empty? ? '' : " (did you mean #{suggestions.join(', ')}?)"
        raise ValidationError, "Unknown #{context} key(s): #{unknown.join(', ')}#{hint}"
      end

      def duration(value)
        match = /\A(\d+(?:\.\d+)?)(ms|s)?\z/.match(value.to_s)
        raise ValidationError, "Invalid duration: #{value}" unless match
        raise ValidationError, "Duration must be finite and at most #{MAX_DURATION}s" if match[1].bytesize > 32

        seconds = match[1].to_f
        seconds /= 1_000 if match[2] == 'ms'
        unless seconds.finite? && seconds.positive? && seconds <= MAX_DURATION
          raise ValidationError, "Duration must be greater than 0 and at most #{MAX_DURATION}s"
        end

        seconds
      end

      def validate_pattern_size!(pattern, context)
        return unless pattern && pattern.to_s.length > MAX_PATTERN_LENGTH

        raise ValidationError, "#{context} pattern must be at most #{MAX_PATTERN_LENGTH} characters"
      end
    end
  end
end

require_relative 'config/include_resolver'
