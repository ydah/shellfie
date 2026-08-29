# Changelog

## 1.1.0 - 2026-08-29

### Added

- Add executable version 2 sessions with `run`, `record`, and `replay`; PTY sessions support command and key input, waits, assertions, hidden steps, redaction, named captures, editable recordings, and offline cassettes.
- Add native selectable-text SVG, accessible HTML, MP4, WebM, event-duration PNG sequences, plain and ANSI-preserving text, structured JSON, and asciinema v2 output. Legacy raster-backed SVG remains available as `svg-raster`.
- Add multiple configured outputs and capture-specific outputs from one session.
- Add JSON Schemas, file/line/column diagnostics, typo suggestions, and `new`, `format`, `compile`, `schema`, `completion`, and include-aware `watch` authoring commands.
- Add typed session variables, reusable and repeated step sets, and OS, shell, Ruby, and configured-environment step conditions.
- Add inferred output names, collision-checked output templates, common aspect presets, bounded parallel batch rendering with `--jobs`, and non-mutating output verification with `generate --check`.
- Add reproducibility manifests and JSON, SARIF, and JUnit validation reports for CI and editor integrations.
- Add a reusable GitHub Action for generating or checking outputs and Docker packaging for a consistent rendering environment.
- Add deterministic animation seeds, separate typing rate, frame timing, and playback speed controls, reverse and ping-pong playback, loop offsets, and format-specific GIF, WebP, and APNG controls.
- Add configurable East Asian Ambiguous width and report the active Unicode and width-table profile through inspection and manifests.
- Add broader terminal behavior for cursor movement, erase and insertion controls, alternate screens, scroll regions, colon-form colors, extended underline styles and colors, blink, conceal, and safe OSC 8 links.

### Changed

- Treat every frame `delay` as a post-action delay; a `type` frame's delay now overrides the global command delay, and `lines` initialize the screen when `frames` are also present.
- Treat an explicit WebP format as static unless the input has frames or `--animate` is supplied.
- Deprecate `--fps` in favor of `--framerate`; use `--typing-rate` to control input speed independently.

### Fixed

- Correct terminal tab stops, backspace behavior, wide-cell overwrites, grapheme-cluster typing, split Unicode input, line feeds, autowrap, and scroll-region editing.
- Correct animation duration rounding, duplicate-frame timing, APNG tail duration, playback-speed timing, and minimum video duration.
- Prevent output collisions before rendering, stream stdout without an output-sized memory copy, preserve existing outputs on failure, and remove partial animation files after errors or interruption.
- Improve live-session prompt and exit synchronization, preserve asynchronous output, honor PTY dimensions and working directories, and terminate leftover child processes.
- Improve `doctor` and dependency checks with real rendering, format delegates, fonts, security policy, and temporary-storage diagnostics.

### Security and reliability

- Add include cycle and chain diagnostics, per-file and aggregate size limits, and an optional symlink-aware root policy for includes and session working directories.
- Add environment allowlists, total and per-step timeouts, bounded regular-expression evaluation, output and control-sequence limits, and rendering workload and temporary-disk budgets.
- Add opt-in rejection of unsupported terminal graphics and an explicit policy for preserving only bounded `http`, `https`, and `mailto` OSC 8 links.

## 1.0.0 - 2026-05-20

### Added

- Add static SVG and WebP output plus animated WebP and APNG output, with format selection by extension or `--format` and binary output through stdout.
- Add batch generation from multiple files and glob patterns, directory outputs, automatic output-directory creation, and `--quiet` and `--verbose` modes.
- Add `inspect` for resolved configuration and output dimensions, and `doctor` for Ruby, ImageMagick, output-directory, and encoding checks.
- Add custom themes, Dracula, One Dark, Solarized Dark, and Catppuccin Mocha color schemes, configurable colors and window decorations, background gradients, font fallbacks, and block, bar, or underline cursors.
- Add reusable YAML includes, line selection and semantic prompt, command, and output colors.
- Add clip, wrap, and scroll overflow modes, exact-size and trimmed canvases, maximum height and line controls, configurable tab width, and per-line or persistent ANSI state.
- Add animation typing jitter and chunking, output and final delays, frame limits, global, adaptive, or theme palettes, optional dithering, and configurable scroll easing.
- Add public Ruby APIs for parsing, validating, rendering, and inspecting configurations.

### Changed

- Correct xterm 256-color values and malformed extended colors, and add dim, reverse, strikethrough, and overline styles plus carriage return, backspace, cursor movement, erase, and tab handling.
- Improve line measurement, clipping, wrapping, fixed-height scrolling, trailing-line preservation, stable animation dimensions, and Windows, Ubuntu, macOS, and headless window rendering.
- Refuse to replace an existing output unless `--force` is supplied, write outputs atomically, report errors on stderr, and distinguish filesystem failures with their own exit code.
- Reject unknown keys, invalid types, unsupported values, excessive lines, frames, characters, pixels, and rendered frames with clearer validation errors before rendering.

## 0.1.1 - 2026-01-12

- Change GIF disposal method from "background" to "none" for improved image handling.

## 0.1.0 - 2026-01-12

- Initial release.
