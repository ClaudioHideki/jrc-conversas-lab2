require 'rails_helper'

RSpec.describe JrcCrm::BackofficeRequest do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:order) do
    account.jrc_crm_sales_orders.create!(owner: actor, source_type: 'manual', order_origin: 'direct_sale', status: 'draft')
  end
  let(:attributes) do
    { account: account, sales_order: order, owner: actor, requested_by: actor,
      title: 'Synthetic protocol collision', request_kind: 'approval', stage: 'approval', status: 'pending' }
  end
  let(:occupied_number) { "BKO-#{Time.zone.today.year}-000042" }

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    order
  end

  it 'regenerates an automatically assigned number already used by the same account' do
    original = described_class.create!(attributes.merge(request_number: occupied_number))
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(42, 43)

    created = described_class.create!(attributes)
    expect(created.request_number).to eq("BKO-#{Time.zone.today.year}-000043")
    expect(original.reload.request_number).to eq(occupied_number)
    expect(account.jrc_crm_backoffice_requests.where(request_number: occupied_number).count).to eq(1)
  end

  it 'keeps protocol uniqueness scoped to the account' do
    foreign = create(:account)
    foreign.enable_features!('jrc_crm', 'jrc_customer_master')
    foreign_actor = create(:user, account: foreign, role: :administrator)
    foreign_order = foreign.jrc_crm_sales_orders.create!(owner: foreign_actor, source_type: 'manual',
                                                        order_origin: 'direct_sale', status: 'draft')
    described_class.create!(attributes.merge(account: foreign, sales_order: foreign_order,
                                            owner: foreign_actor, requested_by: foreign_actor, request_number: occupied_number))
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(42)

    created = described_class.create!(attributes)
    expect(created.request_number).to eq(occupied_number)
    expect(created.account_id).to eq(account.id)
    expect(SecureRandom).to have_received(:random_number).with(1_000_000).once
  end

  it 'preserves supplied protocols and rejects duplicates or blanks without silently renumbering' do
    original = described_class.create!(attributes.merge(request_number: occupied_number))
    expect(SecureRandom).not_to receive(:random_number).with(1_000_000)
    duplicate = described_class.new(attributes.merge(request_number: occupied_number))
    expect(duplicate).not_to be_valid
    expect(duplicate.errors.of_kind?(:request_number, :taken)).to be(true)
    blank = described_class.new(attributes.merge(request_number: ''))
    expect(blank).not_to be_valid
    expect(blank.request_number).to eq('')
    expect(original.reload.request_number).to eq(occupied_number)
  end

  it 'stops after ten occupied automatic candidates and preserves the existing row' do
    original = described_class.create!(attributes.merge(request_number: occupied_number))
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(42)

    expect { described_class.create!(attributes) }.to raise_error(ActiveRecord::RecordInvalid) do |error|
      expect(error.record.errors.of_kind?(:request_number, :taken)).to be(true)
    end
    expect(SecureRandom).to have_received(:random_number).with(1_000_000).exactly(10).times
    expect(original.reload.request_number).to eq(occupied_number)
  end
end
