require 'rails_helper'

RSpec.describe 'Customer360 contract renewal context' do
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
  let(:contract) { account.jrc_crm_contracts.create!(owner: actor, contact: contact, sales_order: order, ends_on: '2026-12-01', renewal_notice_days: 30) }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_crm')
    travel_to Time.iso8601('2026-11-02T02:00:00Z') # November 1 in the account timezone.
  end

  it 'derives the next notice from the real active contract without mutating it or starting a signature' do
    contract.signed_document.attach(io: StringIO.new('SYNTHETIC manual signature fixture, not external verification'), filename: 'synthetic-manual.txt', content_type: 'text/plain')
    contract.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Synthetic test signer')
    original = contract.reload.attributes
    expect { customer.overview }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(customer.overview.fetch(:contract_renewal)).to include(next: include(id: contract.id, contract_number: contract.contract_number,
      ends_on: '2026-12-01', notice_on: '2026-11-01', renewal_notice_days: 30, within_notice_window: true), overdue: 0, undated: 0)
    expect(contract.reload.attributes).to eq(original)
  end

  it 'never treats a draft or an unsigned contract as ready for renewal or weakens the activation guard' do
    contract
    expect(customer.overview.fetch(:contract_renewal)).to eq(next: nil, overdue: 0, undated: 0)
    expect { contract.update!(status: 'active') }.to raise_error(ActiveRecord::RecordInvalid)
    expect(contract.reload.status).to eq('draft')
  end

  it 'respects the existing owner scope and never exposes another owners contract identifier' do
    contract.signed_document.attach(io: StringIO.new('SYNTHETIC manual signature fixture'), filename: 'synthetic-manual.txt', content_type: 'text/plain')
    contract.update!(status: 'active', signature_status: 'signed', signature_mode: 'manual', signed_at: Time.current, signed_by_name: 'Synthetic test signer')
    other = create(:user, account: account, role: :agent)
    scoped = JrcCustomers::Customer360.new(account: account, user: other, account_user: account.account_users.find_by!(user: other), company: company)
    expect(scoped.overview.fetch(:contract_renewal)).to eq(next: nil, overdue: 0, undated: 0)
    expect(scoped.contracts).not_to exist(id: contract.id)
  end

  it 'omits commercial context when the native CRM feature is unavailable' do
    account.disable_features!('jrc_crm')
    expect(customer.overview).not_to have_key(:contract_renewal)
  end
end
