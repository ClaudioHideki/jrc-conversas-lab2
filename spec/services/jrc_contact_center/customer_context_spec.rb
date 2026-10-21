# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CustomerContext do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:phone) { '+5511999999999' }

  it 'resolves customer context using existing master companies and excludes another account' do
    company = account.master_companies.create!(name: 'Customer', customer_code: 'EMP-000001')
    contact = create(:contact, account: account, company_id: company.id, phone_number: phone)
    create(:contact, account: other_account, phone_number: phone)

    result = described_class.new(account: account).by_phone(phone)

    expect(result[:ambiguous]).to be(false)
    expect(result[:contacts]).to contain_exactly(include(id: contact.id.to_s, company: include(id: company.id.to_s, customer_code: 'EMP-000001')))
  end
end
