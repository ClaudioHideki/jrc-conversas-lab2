# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CustomerContext do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:phone) { '+5511999999999' }

  it 'uses the linked contact inside the call account without guessing another customer by phone' do
    contact = create(:contact, account: account, phone_number: phone)
    call = JrcContactCenter::CallSession.new(account: account, contact: contact, ani: '81103', direction: 'inbound')

    result = described_class.new(account: account).for_call(call)

    expect(result[:status]).to eq('identified')
    expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s))
  end

  it 'never treats a short internal extension or a SIP URI as a customer phone' do
    contact = create(:contact, account: account, phone_number: phone)
    contact.update_column(:phone_number, '81103')

    expect(described_class.new(account: account).by_phone('81103')[:contacts]).to be_empty
    expect(described_class.new(account: account).by_phone("sip:#{phone}@pbx.example")[:contacts]).to be_empty
  end

  it 'rejects a call from another account and never returns its linked customer' do
    contact = create(:contact, account: other_account, phone_number: phone)
    call = JrcContactCenter::CallSession.new(account: other_account, contact: contact)

    expect { described_class.new(account: account).for_call(call) }.to raise_error(ArgumentError, 'call account mismatch')
  end

  it 'returns ambiguity explicitly without selecting the first contact' do
    create(:contact, account: account, phone_number: phone)
    contact = create(:contact, account: account)
    contact.update_column(:phone_number, phone.delete_prefix('+'))
    call = JrcContactCenter::CallSession.new(account: account, ani: phone, direction: 'inbound')

    result = described_class.new(account: account).for_call(call)

    expect(result[:status]).to eq('ambiguous')
    expect(result[:ambiguous]).to be(true)
    expect(result[:contacts].length).to eq(2)
  end

  it 'resolves customer context using existing master companies and excludes another account' do
    company = account.master_companies.create!(name: 'Customer', customer_code: 'EMP-000001')
    contact = create(:contact, account: account, company_id: company.id, phone_number: phone)
    create(:contact, account: other_account, phone_number: phone)

    result = described_class.new(account: account).by_phone(phone)

    expect(result[:ambiguous]).to be(false)
    expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s, company: include(id: company.id.to_s, customer_code: 'EMP-000001')))
  end
end
