# frozen_string_literal: true

require "spec_helper"

RSpec.describe Shellfie::Themes do
  describe Shellfie::Themes::Base do
    subject(:theme) { described_class.new }

    it "provides window decoration settings" do
      decoration = theme.window_decoration

      expect(decoration[:title_bar_height]).to eq(28)
      expect(decoration[:corner_radius]).to eq(10)
    end

    it "provides color palette" do
      colors = theme.colors

      expect(colors[:background]).to eq("#1e1e1e")
      expect(colors[:foreground]).to eq("#ffffff")
      expect(colors[:red]).to eq("#ff5555")
    end

    it "provides button colors" do
      expect(theme.button_colors).to eq(%w[#ff5f56 #ffbd2e #27c93f])
    end

    it "resolves color names" do
      expect(theme.color_for(:red)).to eq("#ff5555")
      expect(theme.color_for("#custom")).to eq("#custom")
    end
  end

  describe Shellfie::Themes::MacOS do
    subject(:theme) { described_class.new }

    it "has name 'macos'" do
      expect(theme.name).to eq("macos")
    end

    it "has buttons on the left" do
      expect(theme.buttons_position).to eq(:left)
    end

    it "uses circle button style" do
      expect(theme.button_style).to eq(:circles)
    end
  end

  describe Shellfie::Themes::Ubuntu do
    subject(:theme) { described_class.new }

    it "has name 'ubuntu'" do
      expect(theme.name).to eq("ubuntu")
    end

    it "has buttons on the right" do
      expect(theme.buttons_position).to eq(:right)
    end

    it "has Ubuntu-specific colors" do
      expect(theme.colors[:background]).to eq("#300a24")
    end
  end

  describe Shellfie::Themes::WindowsTerminal do
    subject(:theme) { described_class.new }

    it "has name 'windows'" do
      expect(theme.name).to eq("windows")
    end

    it "has zero corner radius" do
      expect(theme.window_decoration[:corner_radius]).to eq(0)
    end

    it "uses icon button style" do
      expect(theme.button_style).to eq(:icons)
    end
  end
end
