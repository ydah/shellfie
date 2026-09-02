# frozen_string_literal: true

require 'spec_helper'
require 'shellfie/reproducibility_manifest'
require 'tmpdir'

RSpec.describe Shellfie::ReproducibilityManifest do
  it 'fingerprints config, output, environment, and fonts' do
    config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'ok')])

    Dir.mktmpdir do |dir|
      output = File.join(dir, 'out.txt')
      File.write(output, 'ok')
      manifest = described_class.build(config, output_path: output, format: 'txt')

      expect(manifest[:config_sha256]).to match(/\A[0-9a-f]{64}\z/)
      expect(manifest[:output_sha256]).to match(/\A[0-9a-f]{64}\z/)
      expect(manifest[:fonts]).to include(:regular, :italic)
      expect(manifest[:unicode]).to include(
        version: Shellfie::TextMetrics::UNICODE_VERSION, width_table: '1', ambiguous_width: 1
      )
    end
  end

  it 'fingerprints directory outputs deterministically' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'frame.png'), 'frame')

      first = described_class.output_digest(dir)
      second = described_class.output_digest(dir)

      expect(first).to eq(second).and match(/\A[0-9a-f]{64}\z/)
    end
  end
end
