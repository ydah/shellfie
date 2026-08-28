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
- Add reusable session includes, environment allowlists, total timeouts, delayed repeated keys, prompt/line waits, elapsed assertions, and explicit animation seeds.
- Fix colon-form SGR parsing, split grapheme clusters, terminal line-feed semantics, and scroll-region line editing.
- Add inferred output names, collision-checked output templates, PowerShell completion, and TUI/CI/theme-gallery starters.
- Set live PTY dimensions and harden prompt synchronization against prompt-like process output.
- Add theme-switchable accessible HTML plus ANSI-preserving and asciinema v2 transcript exports.
- Preserve existing cells on terminal tab movement and guarantee a decodable minimum video duration.
- Record explicit session sleeps as timeline pauses and allow cassette-only or YAML-only recording.
- Make v2 includes watchable with exact merged provenance and typo suggestions, and make doctor perform a real PNG/policy check.
- Preserve extended underline styles/colors, blink, and conceal through terminal capture and SVG/raster rendering.
- Expose the Unicode/width-table profile and make East Asian Ambiguous width configurable and reproducible.
- Preserve length-bounded, allowlisted OSC 8 links in SVG/HTML behind an explicit OSC policy.

## 0.1.1 - 2026-01-12

- Change GIF disposal method from "background" to "none" for improved image handling.

## 0.1.0 - 2026-01-12

- Initial release.
