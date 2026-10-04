require 'rails_helper'

RSpec.describe JrcCustomers::Taxonomy do
  let(:account) { create(:account) }

  it 'keeps company segments parameterized per account' do
    segment = described_class.create!(account: account, kind: 'segment', name: '  Saúde  ')
    expect(segment.name).to eq('Saúde')
    duplicate = described_class.new(account: account, kind: 'segment', name: 'saúde')
    expect(duplicate).not_to be_valid
  end

  it 'allows the same segment name in another account' do
    described_class.create!(account: account, kind: 'segment', name: 'Saúde')
    other = create(:account)
    expect(described_class.new(account: other, kind: 'segment', name: 'Saúde')).to be_valid
  end
end
