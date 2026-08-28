# frozen_string_literal: true

module Shellfie
  module ConfigDefaults
    VALUES = {
      version: 1,
      theme: "macos",
      window_theme: nil,
      color_scheme: nil,
      colors: {},
      window_decoration: {},
      window: {
        width: 600,
        padding: 20,
        opacity: 1.0,
        visible_lines: nil,
        max_lines: nil,
        max_height: nil,
        wrap: false,
        overflow: "clip",
        margin: nil,
        exact_size: false,
        trim: false,
        tab_width: 8,
        ambiguous_width: 1,
        osc_policy: "ignore",
        ansi_state: "persistent",
        background_gradient: nil,
        scroll_offset: 0.0
      },
      font: {
        family: "Monaco",
        size: 14,
        line_height: 1.4,
        fallback_family: nil,
        italic_family: nil,
        emoji_family: nil
      },
      animation: {
        typing_speed: 80,
        command_delay: 500,
        cursor_blink: true,
        loop: false,
        typing_jitter: 0.0,
        seed: 0,
        typing_chunk_size: 1,
        output_delay: 0,
        final_delay: 1_000,
        max_frames: nil,
        dither: true,
        palette: "global",
        gif_colors: 256,
        gif_optimize: true,
        webp_lossless: true,
        webp_quality: 100,
        webp_method: 4,
        webp_near_lossless: 100,
        apng_prediction: "paeth",
        loop_count: nil,
        scroll_easing: "linear",
        framerate: 30,
        playback_speed: 1.0
      },
      cursor: {
        style: "block",
        color: nil
      },
      limits: {
        max_lines: 10_000,
        max_frames: 500,
        max_render_frames: 2_000,
        max_characters: 200_000,
        max_pixels: 50_000_000,
        max_total_pixels: 2_000_000_000,
        max_temp_bytes: 8_000_000_000
      }
    }.freeze
  end
end
