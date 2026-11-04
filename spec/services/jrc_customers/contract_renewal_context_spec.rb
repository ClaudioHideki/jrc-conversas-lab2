require 'rails_helper'

RSpec.describe JrcCustomers::ContractRenewalContext do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC renewal company') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:customer) { JrcCustomers::Customer360.new(account: account, user: actor, account_user: member, company: company) }
  let(:order) do
    row = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, source_type: 'manual')
    approval = row.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: row, actor: actor).decide!(request: approval, decision: 'approved')
    row.reload
  end
  let(:contract) do
    account.jrc_crm_contracts.create!(owner: actor, contact: contact, sales_order: order, ends_on: '2026-12-01', renewal_notice_days: 30)
  end

  let(:signed_contract) do
    contract.signed_document.attach(io: StringIO.new('SYNTHETIC manual signature fixture, not external verification'),
                                    filename: 'synthetic-manual.txt', content_type: 'text/plain')
    contract.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current,
                     signed_by_name: 'Synthetic test signer')
    contract
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_crm')
    travel_to Time.iso8601('2026-11-02T02:00:00Z') # November 1 in the account timezone.
  end

  it 'derives the next notice from the real active contract without mutating it or starting a signature' do
    signed_contract
    original = contract.reload.attributes
    expect { customer.overview }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(customer.overview.fetch(:contract_renewal)).to include(
      next: include(id: contract.id, contract_number: contract.contract_number, ends_on: '2026-12-01',
                    notice_on: '2026-11-01', renewal_notice_days: 30, within_notice_window: true), overdue: 0, undated: 0
    )
    expect(contract.reload.attributes).to eq(original)
  end

  it 'never treats a draft or an unsigned contract as ready for renewal or weakens the activation guard' do
    contract
    expect(customer.overview.fetch(:contract_renewal)).to eq(next: nil, overdue: 0, undated: 0)
    expect { contract.update!(status: 'active') }.to raise_error(ActiveRecord::RecordInvalid)
    expect(contract.reload.status).to eq('draft')
  end

  it 'respects the existing owner scope and never exposes another owners contract identifier' do
    signed_contract
    other = create(:user, account: account, role: :agent)
    scoped = JrcCustomers::Customer360.new(account: account, user: other, account_user: account.account_users.find_by!(user: other), company: company)
    expect(scoped.overview.fetch(:contract_renewal)).to eq(next: nil, overdue: 0, undated: 0)
    expect(scoped.contracts).not_to exist(id: contract.id)
  end

  it 'omits commercial context when the native CRM feature is unavailable' do
    account.disable_features!('jrc_crm')
    expect(customer.overview).not_to have_key(:contract_renewal)
  end

  it 'selects the nearest authorized future term while retaining overdue and undated counts' do
    signed_contract
    dates = [Date.new(2026, 11, 1), Date.new(2026, 10, 31), nil]
    rows = dates.map do |date|
      row = account.jrc_crm_contracts.create!(owner: actor, contact: contact, sales_order: order, ends_on: date)
      row.signed_document.attach(io: StringIO.new('SYNTHETIC manual-only fixture'), filename: 'synthetic.txt', content_type: 'text/plain')
      row.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Synthetic signer')
      row
    end
    value = customer.overview.fetch(:contract_renewal)
    expect(value).to include(next: include(id: rows.first.id, ends_on: '2026-11-01'), overdue: 1, undated: 1)
    expect(customer.overview[:contracts_active]).to eq(4)
  end

  it 'never includes the contract of a different account in dates or aggregate counts' do
    signed_contract
    foreign_account = create(:account)
    foreign_account.enable_features!('jrc_crm')
    foreign_actor = create(:user, account: foreign_account, role: :administrator)
    foreign_person = create(:contact, account: foreign_account)
    foreign_order = foreign_account.jrc_crm_sales_orders.create!(owner: foreign_actor, contact: foreign_person, source_type: 'manual')
    approval = foreign_order.backoffice_requests.find_by!(request_kind: 'approval')
    JrcCrm::OrderApprovalService.new(order: foreign_order, actor: foreign_actor).decide!(request: approval, decision: 'approved')
    foreign_contract = foreign_account.jrc_crm_contracts.create!(owner: foreign_actor, contact: foreign_person, sales_order: foreign_order)
    expect(customer.contracts).not_to exist(id: foreign_contract.id)
    expect(customer.overview.fetch(:contract_renewal)).to include(next: include(id: contract.id), overdue: 0, undated: 0)
    expect do
      JrcCustomers::Customer360.new(account: account, user: actor, account_user: member,
                                    company: foreign_account.master_companies.create!(name: 'Foreign'))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps operator and unit coverage restrictive even for an administrator and the contract owner' do
    signed_contract
    issuer_a = account.master_companies.create!(name: 'SYNTHETIC operator A', relationship_type: 'internal')
    issuer_b = account.master_companies.create!(name: 'SYNTHETIC operator B', relationship_type: 'internal')
    unit_a = account.jrc_crm_business_units.create!(name: 'SYNTHETIC A', code: 'RENEW-A', operating_company: issuer_a)
    unit_b = account.jrc_crm_business_units.create!(name: 'SYNTHETIC B', code: 'RENEW-B', operating_company: issuer_b)
    order.update!(business_unit: unit_b)
    contract.update!(business_unit: unit_b)
    account.jrc_crm_user_business_units.create!(user: actor, company: issuer_a, business_unit: unit_a,
                                                scope: 'BUSINESS_UNIT', structure_managed: true, active: true)
    hidden = JrcCustomers::Customer360.new(account: account, user: actor, account_user: member, company: company)
    expect(hidden.overview.fetch(:contract_renewal)).to eq(next: nil, overdue: 0, undated: 0)
    order.update!(business_unit: unit_a)
    contract.update!(business_unit: unit_a)
    visible = JrcCustomers::Customer360.new(account: account, user: actor, account_user: member, company: company)
    expect(visible.overview.fetch(:contract_renewal)).to include(next: include(id: contract.id))
  end
end
