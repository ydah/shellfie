# frozen_string_literal: true

module Shellfie
  class AnimationScrollEasing
    def initialize(config)
      @config = config
    end

    def output_delay(base_delay, index, total)
      return base_delay if total <= 1 || easing == "linear"

      progress = index.to_f / (total - 1)
      [(base_delay * delay_factor(progress)).round, 1].max
    end

    def transition_frames(lines, delay:, previous_count:)
      return [{ lines: lines, delay: delay }] unless scroll_transition?(delay, previous_count)

      delays = split_delay(delay, scroll_frame_count(delay))
      delays.each_with_index.map do |frame_delay, index|
        progress = (index + 1).to_f / delays.size
        {
          lines: lines,
          delay: frame_delay,
          window: { scroll_offset: scroll_progress(progress) }
        }
      end
    end

    private

    def easing
      @config.animation[:scroll_easing]
    end

    def scroll_transition?(delay, previous_count)
      visible_lines = @config.window[:visible_lines]
      visible_lines && previous_count >= visible_lines && delay.positive?
    end

    def scroll_frame_count(delay)
      [[[(delay / 40.0).ceil, 1].max, 4].min, delay].min
    end

    def split_delay(delay, count)
      base_delay = delay / count
      remainder = delay % count
      Array.new(count) { |index| base_delay + (index < remainder ? 1 : 0) }
    end

    def delay_factor(progress)
      case easing
      when "ease_in"
        0.75 + progress * 0.5
      when "ease_out"
        1.25 - progress * 0.5
      when "ease_in_out"
        0.75 + (0.5 - (progress - 0.5).abs) * 1.0
      else
        1.0
      end
    end

    def scroll_progress(progress)
      case easing
      when "ease_in"
        progress**2
      when "ease_out"
        1.0 - ((1.0 - progress)**2)
      when "ease_in_out"
        0.5 - Math.cos(progress * Math::PI) / 2.0
      else
        progress
      end
    end
  end
end
