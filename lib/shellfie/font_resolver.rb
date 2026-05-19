# frozen_string_literal: true

module Shellfie
  class FontResolver
    FONT_FILES = {
      "Monaco" => "/System/Library/Fonts/Monaco.ttf",
      "SF Mono" => "/System/Library/Fonts/SFNSMono.ttf",
      "SF Mono Italic" => "/System/Library/Fonts/SFNSMonoItalic.ttf",
      "Menlo" => "/System/Library/Fonts/Menlo.ttc",
      "Courier" => "/System/Library/Fonts/Courier.ttc",
      "Courier New" => "/System/Library/Fonts/Supplemental/Courier New.ttf",
      "DejaVu-Sans-Mono" => "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
      "DejaVu Sans Mono" => "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
    }.freeze

    def initialize(command_provider)
      @command_provider = command_provider
    end

    def resolve(font_config, italic:)
      candidates = []
      candidates << font_config[:italic_family] if italic
      candidates << font_config[:family]
      candidates << font_config[:fallback_family]
      candidates << font_config[:emoji_family]
      candidates << "Menlo"
      candidates << "DejaVu-Sans-Mono"
      candidates << "Courier"

      candidates.compact.flat_map { |candidate| font_candidates(candidate.to_s) }
                .find { |candidate| font_available?(candidate) }
    end

    private

    def font_available?(font)
      return true if File.exist?(font)
      return true if available_fonts.include?(font)

      false
    end

    def font_candidates(font)
      [font, FONT_FILES[font]].compact
    end

    def available_fonts
      @available_fonts ||= begin
        command = @command_provider.call
        if command.empty?
          []
        else
          `#{command} -list font 2>/dev/null`.scan(/^\s*Font:\s+(.+)$/).flatten
        end
      end
    end
  end
end
