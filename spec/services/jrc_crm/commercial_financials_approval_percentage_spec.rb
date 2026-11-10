require 'rails_helper'

RSpec.describe JrcCrm::CommercialFinancials do
  it 'matches the exact approval input vectors through the unmodified native financial calculator' do
    path = Rails.root.join('spec/fixtures/jrc_approvals/discount_percentage_examples.json')
    JSON.parse(File.read(path)).each do |example|
      attributes = { products_cents: example.fetch('base_cents'), snapshot: { discount_percent: example.fetch('percent') } }
      financials = described_class.new(attributes: attributes, items: []).call
      expect(financials.fetch(:discount_cents)).to eq(example.fetch('discount_cents'))
    end
  end
end
