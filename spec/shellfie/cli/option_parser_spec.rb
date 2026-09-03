# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shellfie::CLI::OptionParser do
  it 'returns parsed options and leaves positional arguments' do
    args = ['config.yml', '--scale', '2', '--quiet']

    options = described_class.parse('generate', args)

    expect(options).to be_a(Shellfie::CLI::Options)
    expect(options.to_h).to include(scale: 2, quiet: true)
    expect(args).to eq(['config.yml'])
  end

  it 'builds help from the registered commands and generate options' do
    help = described_class.help

    expect(help).to include('Commands:', 'generate', 'Generate Options:', '--preset', '--jobs', 'Examples:')
  end
end
