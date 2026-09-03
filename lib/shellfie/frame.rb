# frozen_string_literal: true

module Shellfie
  class Frame
    attr_reader :prompt, :type, :output, :delay, :prompt_color, :command_color, :output_color, :screen

    def initialize(prompt: nil, type: nil, output: nil, delay: 0, prompt_color: nil, command_color: nil,
                   output_color: nil, screen: nil)
      @prompt = prompt
      @type = type
      @output = output
      @delay = delay
      @prompt_color = prompt_color
      @command_color = command_color
      @output_color = output_color
      @screen = screen
      freeze
    end

    def to_h
      {
        prompt: prompt,
        type: type,
        output: output,
        delay: delay,
        prompt_color: prompt_color,
        command_color: command_color,
        output_color: output_color,
        screen: screen
      }.compact
    end

    def to_s
      [prompt, type, output, screen, delay].compact.join("\n")
    end
  end
end
