# frozen_string_literal: true

module Shellfie
  class AnimationTimeline
    Event = Struct.new(:kind, :frame, keyword_init: true)

    def initialize(config)
      @config = config
    end

    def each
      return enum_for(:each) unless block_given?

      @config.frames.each do |frame|
        yield Event.new(kind: :command, frame: frame) if frame.type
        yield Event.new(kind: :output, frame: frame) if frame.output
        yield Event.new(kind: :pause, frame: frame) if pause_frame?(frame)
      end
    end

    private

    def pause_frame?(frame)
      frame.delay&.positive? && frame.output.nil? && frame.type.nil?
    end
  end
end
