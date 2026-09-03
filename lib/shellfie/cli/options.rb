# frozen_string_literal: true

module Shellfie
  class CLI
    Options = Struct.new(
      :template,
      :force,
      :check,
      :format,
      :output,
      :interval,
      :json,
      :theme,
      :animate,
      :scale,
      :width,
      :preset,
      :typing_rate,
      :framerate,
      :seed,
      :playback_speed,
      :overflow,
      :wrap,
      :exact_size,
      :shadow,
      :transparent,
      :headless,
      :jobs,
      :quiet,
      :verbose,
      :manifest,
      :cassette,
      :yaml,
      keyword_init: true
    )
  end
end
