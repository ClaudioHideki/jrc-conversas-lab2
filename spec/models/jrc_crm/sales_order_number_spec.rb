require 'rails_helper'

RSpec.describe JrcCrm::SalesOrder do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:attributes) { { owner: actor, source_type: 'manual', order_origin: 'direct_sale' } }
  let(:number) { "PED-#{Time.zone.today.year}-123456" }

  it 'retries a generated number already occupied in this account without modifying the existing order' do
    original = account.jrc_crm_sales_orders.create!(**attributes, order_number: number)
    before = original.attributes.deep_dup
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(123_456, 123_457)
    order = account.jrc_crm_sales_orders.create!(attributes)
    expect(order.order_number).to eq("PED-#{Time.zone.today.year}-123457")
    expect(original.reload.attributes).to eq(before)
  end

  it 'preserves an explicitly supplied number and native duplicate rejection' do
    order = account.jrc_crm_sales_orders.create!(**attributes, order_number: number)
    expect(order.order_number).to eq(number)
    expect { account.jrc_crm_sales_orders.create!(**attributes, order_number: number) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.jrc_crm_sales_orders.count).to eq(1)
  end

  it 'allows the same human number in another account without using its records to allocate this account number' do
    account.jrc_crm_sales_orders.create!(**attributes, order_number: number)
    foreign = create(:account)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(123_456)
    order = foreign.jrc_crm_sales_orders.create!(owner: foreign_actor, source_type: 'manual', order_origin: 'direct_sale')
    expect([order.account_id, order.order_number]).to eq([foreign.id, number])
  end

  it 'fails with native validation after bounded collisions instead of looping or overwriting data' do
    account.jrc_crm_sales_orders.create!(**attributes, order_number: number)
    allow(SecureRandom).to receive(:random_number).and_call_original
    allow(SecureRandom).to receive(:random_number).with(1_000_000).and_return(123_456)
    expect { account.jrc_crm_sales_orders.create!(attributes) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(SecureRandom).to have_received(:random_number).with(1_000_000).exactly(10).times
    expect(account.jrc_crm_sales_orders.count).to eq(1)
  end
end
