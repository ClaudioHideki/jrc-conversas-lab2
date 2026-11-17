
require 'rails_helper'

RSpec.describe JrcContactCenter::ConfigurationRevision do
  let(:account) { create(:account) }
  let(:unit) do
    JrcContactCenter::Unit.create!(
      account: account, code: 'REVISION', name: 'Revision', kind: 'sac',
      settings: { 'b' => 2, 'a' => { 'z' => 2, 'x' => 1 } }
    )
  end

  it 'keeps the revision stable across persisted JSON key ordering' do
    expected = described_class.token(unit.reload)
    unit.settings = { 'a' => { 'x' => 1, 'z' => 2 }, 'b' => 2 }
    expect(described_class.token(unit)).to eq(expected)
  end

  it 'includes microsecond changes instead of truncating the persisted timestamp' do
    expected = described_class.token(unit)
    unit.updated_at += 1.microsecond
    expect(described_class.token(unit)).not_to eq(expected)
  end

  it 'includes the private configuration without returning it as a token value' do
    expected = described_class.token(unit)
    unit.settings['private'] = 'NOT-THE-TOKEN'
    expect(described_class.token(unit)).to match(/\A[a-f0-9]{64}\z/)
    expect(described_class.token(unit)).not_to eq(expected)
    expect(described_class.token(unit)).not_to include('NOT-THE-TOKEN')
  end
end
