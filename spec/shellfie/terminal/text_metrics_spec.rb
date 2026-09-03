# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Shellfie::Terminal::TextMetrics do
  it 'reports its Unicode profile and supports ambiguous-width terminals' do
    expect(described_class::UNICODE_VERSION).to match(/\A\d+\.\d+\.\d+\z|unknown/)
    expect(described_class.cell_width('·', ambiguous_width: 1)).to eq(1)
    expect(described_class.cell_width('·', ambiguous_width: 2)).to eq(2)
  end

  it 'treats emoji presentation graphemes as two cells' do
    expect(described_class.grapheme_width('1️⃣')).to eq(2)
    expect(described_class.grapheme_width('©️')).to eq(2)
  end
end
