# frozen_string_literal: true

require "cgi/escape"
require_relative "svg_renderer"

module Shellfie
  class HtmlRenderer
    def initialize(config:, theme:)
      @config = config
      @svg_renderer = SvgRenderer.new(config: config, theme: theme)
    end

    def render(geometry, output_path, transparent: false)
      svg = @svg_renderer.to_svg(geometry, transparent: transparent).sub(/\A<\?xml[^>]+>\s*/, "")
      transcript = geometry[:lines].map { |line| line[:segments].map(&:text).join }.join("\n")
      File.write(output_path, <<~HTML)
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>#{escape(@config.title)}</title>
          <style>
            :root { color-scheme: light dark; }
            :root[data-theme="light"] { color-scheme: light; }
            :root[data-theme="dark"] { color-scheme: dark; }
            body { margin: 0; display: grid; min-height: 100vh; place-items: center; background: Canvas; }
            main { max-width: 100%; overflow: auto; }
            button { position: fixed; inset: 1rem 1rem auto auto; font: inherit; }
            svg { display: block; max-width: 100%; height: auto; }
            .transcript { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: pre; }
          </style>
        </head>
        <body>
          <button type="button" aria-label="Toggle color theme">Theme</button>
          <main aria-label="#{escape(@config.title)}">#{svg}<pre class="transcript">#{escape(transcript)}</pre></main>
          <script>
            document.querySelector('button').addEventListener('click', () => {
              const root = document.documentElement;
              root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
            });
          </script>
        </body>
        </html>
      HTML
    end

    private

    def escape(value)
      CGI.escapeHTML(value.to_s)
    end
  end
end
