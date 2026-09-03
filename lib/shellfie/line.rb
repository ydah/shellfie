# frozen_string_literal: true

module Shellfie
  class Line
    attr_reader :prompt, :command, :output, :prompt_color, :command_color, :output_color, :selected

    def initialize(prompt: nil, command: nil, output: nil, prompt_color: nil, command_color: nil, output_color: nil,
                   selected: false)
      @prompt = prompt
      @command = command
      @output = output
      @prompt_color = prompt_color
      @command_color = command_color
      @output_color = output_color
      @selected = selected
      freeze
    end

    def to_h
      {
        prompt: prompt,
        command: command,
        output: output,
        prompt_color: prompt_color,
        command_color: command_color,
        output_color: output_color,
        selected: selected
      }.compact
    end

    def to_s
      [prompt, command, output].compact.join("\n")
    end
  end
end
