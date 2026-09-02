# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shellfie do
  describe '.validate' do
    it 'returns true for valid configs' do
      allow(Shellfie::Parser).to receive(:parse).with('config.yml').and_return(Shellfie::Config.new(lines: []))

      expect(described_class.validate('config.yml')).to be true
    end
  end

  describe '.render' do
    it 'renders static configs through Renderer' do
      config = Shellfie::Config.new(lines: [Shellfie::Line.new(output: 'test')])
      renderer = instance_double(Shellfie::Renderer)
      allow(Shellfie::Renderer).to receive(:new).with(config).and_return(renderer)
      allow(renderer).to receive(:render).and_return('out.png')

      expect(described_class.render(config, output: 'out.png')).to eq('out.png')
      expect(renderer).to have_received(:render).with('out.png', scale: 1, shadow: true, transparent: false,
                                                                 format: nil)
    end
  end
end
