require 'rails_helper'

RSpec.describe JrcCustomers::BackofficeContext, :approval_core, :authority_core do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:company) { domain.fetch(:customer) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_crm contact_manage]) }
  let(:service) { described_class.new(account: account, actor: actor, company: company) }

  before do
    raise 'Owned master context database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    domain
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
  end

  it 'uses the native company, owner and unit scope before totals, options and caller filters' do
    other_company = account.master_companies.create!(name: 'TESTE SINTÉTICO — Outra empresa')
    other_contact = create(:contact, account: account, company_id: other_company.id)
    other_order = account.jrc_crm_sales_orders.create!(owner: actor, contact: other_contact, business_unit: domain[:unit], status: 'approved')
    account.jrc_crm_backoffice_requests.create!(sales_order: other_order, owner: actor, requested_by: actor, contact: other_contact,
                                                business_unit: domain[:unit], title: 'PRIVATE_OTHER_COMPANY')
    other_owner = create(:user, account: account, role: :agent)
    account.jrc_crm_backoffice_requests.create!(sales_order: domain[:order], owner: other_owner, requested_by: other_owner,
                                                contact: domain[:customer_person], business_unit: domain[:unit],
                                                request_kind: 'change', title: 'PRIVATE_OTHER_OWNER')
    result = service.call(params: { company_id: other_company.id, owner_id: other_owner.id, business_unit_id: 0 })
    expect(result[:data].pluck(:id)).to eq([domain[:operation].id])
    expect(result[:meta]).to include(total: 1)
    expect(result[:options][:owners].pluck(:id)).to eq([actor.id])
    expect(result.to_json).not_to include('PRIVATE_OTHER_COMPANY', 'PRIVATE_OTHER_OWNER')
    expect(JrcBackoffice::ContractAccess.new(account: account, actor: actor).request(domain[:operation].id)).to eq(domain[:operation])
  end

  it 'denies revoked CRM access and excludes revoked unit records on an existing service instance' do
    expect(service.call[:meta][:total]).to eq(1)
    role.update!(permissions: ['contact_manage'])
    expect { service.call }.to raise_error(Pundit::NotAuthorizedError)
    role.update!(permissions: %w[jrc_crm contact_manage])
    account.jrc_crm_user_business_units.where(user: actor).each { |grant| grant.update!(active: false) }
    expect(service.call[:meta][:total]).to eq(0)
    expect do
      JrcBackoffice::ContractAccess.new(account: account, actor: actor).request(domain[:operation].id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a company or actor from another account without granting access by supplied IDs' do
    foreign_account = create(:account)
    foreign_company = foreign_account.master_companies.create!(name: 'PRIVATE_FOREIGN_COMPANY')
    foreign_actor = create(:user, account: foreign_account, role: :administrator)
    expect do
      described_class.new(account: account, actor: actor, company: foreign_company).call
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      described_class.new(account: account, actor: foreign_actor, company: company).call
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'paginates native requests on the server without repeating records or changing their state' do
    24.times do |index|
      account.jrc_crm_backoffice_requests.create!(sales_order: domain[:order], owner: actor, requested_by: actor,
                                                  contact: domain[:customer_person], business_unit: domain[:unit],
                                                  request_kind: 'change', title: "TESTE SINTÉTICO — Página #{index}")
    end
    first = service.call(params: { page: 1, per_page: 20 })
    second = service.call(params: { page: 2, per_page: 20 })
    expect(first[:meta]).to include(total: 25, pages: 2, per_page: 20)
    expect([first[:data].length, second[:data].length]).to eq([20, 5])
    expect(first[:data].pluck(:id) & second[:data].pluck(:id)).to be_empty
    expect(domain[:operation].reload.status).to eq('pending')
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'returns only safe event metadata from authorized company origins' do
    before_count = service.call(params: { view: 'history' })[:meta][:total]
    event = JrcCustomers::Audit.record!(account: account, actor: actor, resource: domain[:operation], event_type: 'backoffice_updated',
                                        metadata: { note: 'PRIVATE_AUDIT_NOTE' }, from_value: { secret: 'PRIVATE_OLD_VALUE' })
    result = service.call(params: { view: 'history', page: 1, per_page: 1 })
    expect(result[:meta]).to include(total: before_count + 1, page: 1, pages: before_count + 1, per_page: 1)
    expect(result[:data].pluck(:id)).to eq([event.id])
    expect(result[:data].first.keys.map(&:to_s).sort).to eq(%w[created_at event_type id request_id])
    expect(result.to_json).not_to include('PRIVATE_AUDIT_NOTE', 'PRIVATE_OLD_VALUE', 'metadata', 'from_value')
  end
end
