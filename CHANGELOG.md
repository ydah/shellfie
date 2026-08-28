# Changelog

## 1.1.0 - 2026-08-28

- Make frame delays consistent and preserve `lines` as the initial animation screen.
- Render native selectable-text SVG, with `svg-raster` kept as an explicit legacy format.
- Fix static WebP mode, terminal tab/backspace behavior, grapheme typing, include diagnostics, batch collisions, and stdout memory use.
- Add explicit typing rate, frame timing, playback speed, workload limits, and stronger dependency checks.
- Add an optional PTY session runner with live/exit/stable waits, assertions, named capture outputs, redaction, multi-output rendering, editable recording, and offline cassette replay.
- Add a shared terminal screen model, duplicate-frame coalescing, MP4/WebM, event-duration PNG sequences, accessible HTML, and semantic TXT/JSON transcripts.
- Add JSON Schemas, source locations with typo suggestions, authoring commands, manifests, a GitHub Action, Docker packaging, and project security/contribution metadata.
- Add v2 inspection, step working directories, text-golden assertions, include-aware watching, exact nested diagnostics, and terminal-edge autowrap handling.
- Align schema and runtime limits for steps, captures, patterns, environment names, and output formats.

## 0.1.1 - 2026-01-12

- Change GIF disposal method from "background" to "none" for improved image handling.

## 0.1.0 - 2026-01-12

- Initial release.
