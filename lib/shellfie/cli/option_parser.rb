# frozen_string_literal: true

require 'optparse'

module Shellfie
  class CLI
    class OptionParser
      class << self
        def parse(command, args)
          options = Options.new
          parser_for(command, options)&.parse!(args)
          options.freeze
        end

        private

        def parser_for(command, options)
          case command
          when 'generate', 'g' then generate_parser(options)
          when 'run' then session_parser(options, record: false)
          when 'record' then session_parser(options, record: true)
          when 'replay' then replay_parser(options)
          when 'new' then new_parser(options)
          when 'format' then format_parser(options)
          when 'compile' then compile_parser(options)
          when 'watch' then watch_parser(options)
          when 'validate' then validate_parser(options)
          when 'inspect' then inspect_parser(options)
          end
        end

        def new_parser(options)
          options.template = 'static'
          ::OptionParser.new do |opts|
            opts.on('--template NAME', 'static, animation, run, tui, ci, or theme-gallery') do |name|
              options.template = name
            end
            opts.on('--force', 'Overwrite an existing file') { options.force = true }
          end
        end

        def format_parser(options)
          ::OptionParser.new do |opts|
            opts.on('--check', 'Exit unsuccessfully if formatting differs') { options.check = true }
          end
        end

        def compile_parser(options)
          options.format = 'json'
          ::OptionParser.new do |opts|
            opts.on('--format FORMAT', 'json or yaml') { |value| options.format = value }
          end
        end

        def watch_parser(options)
          options.interval = 0.5
          ::OptionParser.new do |opts|
            opts.on('-o', '--output PATH', 'Output path') { |path| options.output = path }
            opts.on('--interval SECONDS', Float, 'Polling interval') { |value| options.interval = value }
          end
        end

        def validate_parser(options)
          options.format = 'text'
          ::OptionParser.new do |opts|
            opts.on('--format FORMAT', 'text, json, sarif, or junit') { |value| options.format = value }
          end
        end

        def inspect_parser(options)
          ::OptionParser.new do |opts|
            opts.on('--json', 'Print machine-readable JSON') { options.json = true }
          end
        end

        def generate_parser(options)
          ::OptionParser.new do |opts|
            opts.banner = 'Usage: shellfie generate INPUT_FILE [options]'
            opts.on('-o', '--output PATH', 'Output path or {name}-{theme}-{scale}.{format} template') do |path|
              options.output = path
            end
            opts.on('-t', '--theme NAME', 'Override theme (macos, ubuntu, windows)') { |value| options.theme = value }
            opts.on('-a', '--animate', 'Render animated output') { options.animate = true }
            opts.on('-s', '--scale FACTOR', 'Output scale (1, 2, 3)') { |value| options.scale = parse_scale(value) }
            opts.on('-w', '--width PIXELS', Integer, 'Override width') { |value| options.width = value }
            opts.on('--preset NAME', 'readme, ogp, widescreen, standard, or vertical') do |name|
              unless Generate::ASPECT_PRESETS.key?(name)
                raise ValidationError,
                      "preset must be one of: #{Generate::ASPECT_PRESETS.keys.join(', ')}"
              end

              options.preset = name
            end
            opts.on('--typing-rate CPS', Integer, 'Typing rate in characters per second') do |value|
              options.typing_rate = parse_rate(value)
            end
            opts.on('--framerate FPS', Integer, 'Output timing precision in frames per second') do |value|
              options.framerate = parse_framerate(value)
            end
            opts.on('--fps FPS', Integer, 'Deprecated alias for --framerate') do |value|
              warn 'Warning: --fps is deprecated; use --framerate'
              options.framerate = parse_framerate(value)
            end
            opts.on('--seed N', Integer, 'Deterministic animation seed') { |value| options.seed = parse_seed(value) }
            opts.on('--playback-speed FACTOR', Float, 'Playback speed multiplier') do |value|
              options.playback_speed = parse_playback_speed(value)
            end
            opts.on('--overflow MODE', 'Line overflow mode (clip, wrap, scroll)') { |value| options.overflow = value }
            opts.on('--wrap', 'Wrap long lines') { options.wrap = true }
            opts.on('--no-wrap', 'Clip long lines') { options.wrap = false }
            opts.on('--exact-size', 'Make output canvas match the configured window size') { options.exact_size = true }
            opts.on('--no-shadow', 'Disable shadow effect') { options.shadow = false }
            opts.on('--transparent', 'Transparent background') { options.transparent = true }
            opts.on('--no-header', 'Disable window header (headless mode)') { options.headless = true }
            opts.on('--format FORMAT',
                    'Output format (png, gif, svg, svg-raster, webp, apng, mp4, webm, ' \
                    'png-sequence, html, txt, ansi, json, asciicast)') do |value|
              options.format = parse_output_format(value)
            end
            opts.on('--force', 'Overwrite existing output files') { options.force = true }
            opts.on('--check', 'Fail if the existing output differs without replacing it') { options.check = true }
            opts.on('--jobs N', Integer, 'Render up to N inputs in parallel (1-32)') do |value|
              options.jobs = parse_jobs(value)
            end
            opts.on('--quiet', 'Suppress non-error output') { options.quiet = true }
            opts.on('--verbose', 'Print extra progress information') { options.verbose = true }
            opts.on('--manifest PATH', 'Write a reproducibility manifest') { |path| options.manifest = path }
          end
        end

        def session_parser(options, record:)
          ::OptionParser.new do |opts|
            opts.banner = "Usage: shellfie #{record ? 'record' : 'run'} SESSION.yml [options]"
            session_output_options(opts, options)
            opts.on('--cassette PATH', 'Write an offline replay cassette') { |path| options.cassette = path }
            opts.on('--yaml PATH', 'Write an editable compose recording') { |path| options.yaml = path } if record
          end
        end

        def replay_parser(options)
          ::OptionParser.new do |opts|
            opts.banner = 'Usage: shellfie replay SESSION.json [options]'
            session_output_options(opts, options)
            opts.on('-t', '--theme NAME', 'Render theme') { |value| options.theme = value }
          end
        end

        def session_output_options(parser, options)
          parser.on('-o', '--output PATH', 'Output path (overrides config outputs)') { |path| options.output = path }
          parser.on('--format FORMAT', 'Output format') { |value| options.format = parse_output_format(value) }
          parser.on('-a', '--animate', 'Render the captured timeline') { options.animate = true }
          parser.on('--force', 'Overwrite existing outputs') { options.force = true }
          parser.on('--quiet', 'Suppress generated paths') { options.quiet = true }
        end

        def parse_scale(value)
          scale = Integer(value, exception: false)
          return scale if [1, 2, 3].include?(scale)

          raise ValidationError, 'scale must be 1, 2, or 3'
        end

        def parse_rate(value)
          rate = Integer(value, exception: false)
          return rate if rate&.between?(1, 1_000)

          raise ValidationError, 'typing rate must be between 1 and 1000'
        end

        def parse_framerate(value)
          framerate = Integer(value, exception: false)
          return framerate if framerate&.between?(1, 120)

          raise ValidationError, 'framerate must be between 1 and 120'
        end

        def parse_playback_speed(value)
          speed = Float(value, exception: false)
          return speed if speed&.positive? && speed <= 100

          raise ValidationError, 'playback speed must be greater than 0 and at most 100'
        end

        def parse_seed(value)
          seed = Integer(value, exception: false)
          return seed if seed&.between?(0, 2_147_483_647)

          raise ValidationError, 'seed must be between 0 and 2147483647'
        end

        def parse_jobs(value)
          jobs = Integer(value, exception: false)
          return jobs if jobs&.between?(1, 32)

          raise ValidationError, 'jobs must be between 1 and 32'
        end

        def parse_output_format(value)
          format = value.to_s.downcase
          return format if Generate::SUPPORTED_FORMATS.include?(format)

          raise ValidationError, "format must be one of: #{Generate::SUPPORTED_FORMATS.join(', ')}"
        end
      end
    end
  end
end
