# frozen_string_literal: true

require "spec_helper"
require "shellfie/dependency_checker"

RSpec.describe Shellfie::DependencyChecker do
  it "does not require ImageMagick's APNG delegate when ffmpeg owns APNG output" do
    expect(described_class.send(:required_formats)).to contain_exactly("PNG", "GIF", "WEBP", "SVG")
  end
end
