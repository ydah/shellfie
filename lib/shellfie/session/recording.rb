# frozen_string_literal: true

require_relative '../config'
require_relative '../parser'
require_relative '../terminal/screen'

module Shellfie
  module Session
    class Recording
      attr_reader :events, :captures, :exit_status, :screen

      def initialize(columns:, rows:, title: 'Terminal Session', events: [], captures: {}, exit_status: nil)
        unless columns.is_a?(Integer) && columns.between?(1, 500) && rows.is_a?(Integer) && rows.between?(1, 200)
          raise ParseError, 'Invalid session dimensions'
        end

        @title = title
        @events = events
        @captures = captures
        @exit_status = exit_status
        @screen = Terminal::Screen.new(columns: columns, rows: rows)
        events.each { |event| @screen.feed(event[:text].to_s) if event.fetch(:visible, true) }
      end

      def record(text, delay: 0, visible: true, status: nil)
        screen.feed(text) if visible
        event = { text: visible ? text : '', delay: delay, visible: visible, status: status }
        events << event
        @exit_status = status unless status.nil?
        event
      end

      def capture(name)
        captures[name] = screen.render_lines
      end

      def render_config(theme:, options: {}, animated: false, lines: nil)
        base = {
          theme: theme,
          title: @title,
          window: options.fetch(:window, {}),
          font: options.fetch(:font, {}),
          animation: options.fetch(:animation, {}),
          headless: options.fetch(:headless, false)
        }
        return animated_render_config(base, lines) if animated

        static_render_config(base, lines)
      end

      def editable_config
        frames = []
        each_snapshot do |event, snapshot|
          frames << {
            'screen' => snapshot,
            'delay' => [(event[:delay].to_f * 1_000).round, 1].max
          }
        end
        {
          'version' => 1,
          'title' => @title,
          'window' => { 'width' => screen.columns * 8, 'visible_lines' => screen.rows },
          'frames' => frames
        }
      end

      def to_h
        {
          version: 1,
          title: @title,
          columns: screen.columns,
          rows: screen.rows,
          events: events,
          captures: captures,
          exit_status: exit_status
        }
      end

      private

      def animated_render_config(base, lines)
        raise ValidationError, 'Captured screens cannot be rendered as animations' if lines

        frames = []
        each_snapshot do |event, snapshot|
          frames << Frame.new(screen: snapshot, delay: [(event[:delay].to_f * 1_000).round, 1].max)
        end
        Shellfie::Config.new(**base, frames: frames)
      end

      def static_render_config(base, lines)
        rendered_lines = lines || screen.render_lines
        Shellfie::Config.new(**base, lines: rendered_lines.map { |line| Line.new(output: line) })
      end

      def each_snapshot
        replay = Terminal::Screen.new(columns: screen.columns, rows: screen.rows)
        count = characters = 0
        events.each do |event|
          next unless event[:visible]

          text = event[:text].to_s
          next if text.empty? && !event[:delay].to_f.positive?

          count += 1
          if count > Shellfie::Config::DEFAULTS[:limits][:max_frames]
            raise ResourceLimitError, "Too many session frames (max #{Shellfie::Config::DEFAULTS[:limits][:max_frames]})"
          end

          replay.feed(text) unless text.empty?
          snapshot = event[:screen] || replay.render_lines
          characters += snapshot.sum(&:length)
          if characters > Shellfie::Config::DEFAULTS[:limits][:max_characters]
            raise ResourceLimitError,
                  "Session snapshots are too large (max #{Shellfie::Config::DEFAULTS[:limits][:max_characters]} characters)"
          end

          yield event, snapshot
        end
      end
    end
  end
end
