# frozen_string_literal: true

require_relative "config"
require_relative "parser"
require_relative "terminal_screen"

module Shellfie
  class Session
    attr_reader :events, :captures, :exit_status, :screen

    def initialize(columns:, rows:, title: "Terminal Session", events: [], captures: {}, exit_status: nil)
      unless columns.is_a?(Integer) && columns.between?(1, 500) && rows.is_a?(Integer) && rows.between?(1, 200)
        raise ParseError, "Invalid session dimensions"
      end

      @title = title
      @events = events
      @captures = captures
      @exit_status = exit_status
      @screen = TerminalScreen.new(columns: columns, rows: rows)
      events.each { |event| @screen.feed(event[:text].to_s) if event.fetch(:visible, true) }
    end

    def record(text, delay: 0, visible: true, status: nil)
      screen.feed(text) if visible
      event = { text: visible ? text : "", delay: delay, visible: visible, status: status }
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
      if animated
        raise ValidationError, "Captured screens cannot be rendered as animations" if lines

        frames = []
        each_snapshot do |event, snapshot|
          frame = Frame.new(screen: snapshot, delay: [(event[:delay].to_f * 1_000).round, 1].max)
          frames << frame
        end
        Config.new(**base, frames: frames)
      else
        Config.new(**base, lines: (lines || screen.render_lines).map { |line| Line.new(output: line) })
      end
    end

    def compose_hash
      frames = []
      each_snapshot do |event, snapshot|
        frames << {
          "screen" => snapshot,
          "delay" => [(event[:delay].to_f * 1_000).round, 1].max
        }
      end
      {
        "version" => 1,
        "title" => @title,
        "window" => { "width" => screen.columns * 8, "visible_lines" => screen.rows },
        "frames" => frames
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

    def each_snapshot
      replay = TerminalScreen.new(columns: screen.columns, rows: screen.rows)
      count = characters = 0
      events.each do |event|
        next unless event[:visible]

        text = event[:text].to_s
        next if text.empty? && !event[:delay].to_f.positive?

        count += 1
        raise ResourceLimitError, "Too many session frames (max #{Config::DEFAULTS[:limits][:max_frames]})" if count > Config::DEFAULTS[:limits][:max_frames]

        replay.feed(text) unless text.empty?
        snapshot = event[:screen] || replay.render_lines
        characters += snapshot.sum(&:length)
        if characters > Config::DEFAULTS[:limits][:max_characters]
          raise ResourceLimitError, "Session snapshots are too large (max #{Config::DEFAULTS[:limits][:max_characters]} characters)"
        end
        yield event, snapshot
      end
    end
  end
end
