# shellfie

Generate terminal screenshot-style images and animations from YAML.

<p align="center">
  <img src="assets/logo-header.svg" alt="shellfie">
</p>

<p align="center">
  <a href="https://rubygems.org/gems/shellfie"><img src="https://img.shields.io/gem/v/shellfie.svg?colorB=319e8c" alt="Gem Version"></a>
  <a href="https://rubygems.org/gems/shellfie"><img src="https://img.shields.io/gem/dt/shellfie.svg" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/ruby-%3E%3D%203.0-ruby.svg" alt="Ruby Version">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License">
</p>

<p align="center">
  <img src="examples/demo.gif" alt="shellfie demo" width="560">
</p>

## Install

Requirements:

- Ruby 3.0+
- ImageMagick 7+

```bash
brew install imagemagick
gem install shellfie
```

For Bundler:

```ruby
gem "shellfie"
```

## Quick Start

Create `terminal.yml`:

```yaml
theme: macos
title: "Terminal - zsh"

window:
  width: 600
  padding: 20

lines:
  - prompt: "$ "
    command: "echo hello"
  - output: "hello"
```

Generate an image:

```bash
shellfie generate terminal.yml -o terminal.png
```

Use `shf` as a short alias for `shellfie`.

## CLI

```bash
shellfie generate config.yml -o output.png
shellfie generate config.yml -o demo.gif --animate
shellfie generate config.yml -o output.svg --format svg
shellfie generate config.yml -o output.png --scale 2 --no-shadow
shellfie generate config.yml -o output.png --no-header
shellfie validate config.yml
shellfie themes
shellfie init
```

Common `generate` options:

| Option | Description |
| --- | --- |
| `-o, --output PATH` | Output path |
| `-t, --theme NAME` | Override theme |
| `-a, --animate` | Render animation |
| `-s, --scale FACTOR` | Output scale: `1`, `2`, or `3` |
| `-w, --width PIXELS` | Override window width |
| `--format FORMAT` | `png`, `gif`, `svg`, `webp`, or `apng` |
| `--fps FPS` | Override animation typing FPS |
| `--overflow MODE` | `clip`, `wrap`, or `scroll` |
| `--no-shadow` | Disable shadow |
| `--transparent` | Transparent background |
| `--no-header` | Headless output |
| `--force` | Overwrite existing files |

Static output supports `png`, `svg`, and `webp`.
Animated output supports `gif`, `webp`, and `apng`.

## Configuration

Static content uses `lines`:

```yaml
theme: macos
title: "Terminal"

window:
  width: 600
  padding: 20
  visible_lines: 8
  overflow: clip

font:
  family: Monaco
  size: 14
  line_height: 1.4

lines:
  - prompt: "$ "
    command: "gem install shellfie"
  - output: |
      Successfully installed shellfie
      1 gem installed
```

Animations use `frames`:

```yaml
theme: macos
title: "Demo"

animation:
  typing_speed: 50
  command_delay: 500
  cursor_blink: true
  loop: true
  palette: global
  dither: true
  scroll_easing: ease_out

frames:
  - prompt: "$ "
    type: "echo hello"
    delay: 500
  - output: "hello"
    delay: 1000
```

Useful top-level keys:

| Key | Purpose |
| --- | --- |
| `theme` | `macos`, `ubuntu`, `windows`, or `custom` |
| `color_scheme` | Built-in color scheme such as `dracula` |
| `colors` | Theme color overrides |
| `window` | Size, padding, wrapping, clipping, scrolling |
| `font` | Font family, size, line height |
| `animation` | Typing speed, delays, loop, palette, easing |
| `cursor` | Cursor style and color |
| `headless` | Hide window chrome |
| `lines` | Static terminal content |
| `frames` | Animated terminal content |

ANSI colors and styles are supported in `prompt`, `command`, and `output`, including 8-color, bright, 256-color, and RGB escape sequences.

## Themes

Built-in window themes:

- `macos`
- `ubuntu`
- `windows`

Headless output removes window chrome:

```yaml
headless: true
```

or:

```bash
shellfie generate config.yml -o output.png --no-header
```

## Development

```bash
bundle install
bundle exec rspec
```

## License

[MIT](LICENSE)
