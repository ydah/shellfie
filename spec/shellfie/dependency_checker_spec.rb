# frozen_string_literal: true

require "spec_helper"
require "shellfie/dependency_checker"

RSpec.describe Shellfie::DependencyChecker do
  it "does not require ImageMagick's APNG delegate when ffmpeg owns APNG output" do
    expect(described_class.send(:required_formats)).to contain_exactly("PNG", "GIF", "WEBP", "SVG")
  end

  it "smoke tests rendering and reports the active security policy" do
    details = described_class.imagemagick_details
    checks = described_class.doctor

    expect(details).to include(:render_ok, :policy)
    expect(checks.map { |check| check[:name] }).to include("Image render", "Security policy")
  end
end
