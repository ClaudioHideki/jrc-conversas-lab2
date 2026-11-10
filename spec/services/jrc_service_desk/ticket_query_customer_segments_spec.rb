require 'rails_helper'

RSpec.describe JrcServiceDesk::TicketQuery, type: :service do
  include_context 'JRC Service Desk domain'

  let(:taxonomy) do
    JrcCustomers::Taxonomy.create!(account: sd_account, name: 'Selected service customers', kind: 'segment', modules: ['service_desk'])
  end
  let(:company) { sd_account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:selected) { sd_ticket }
  let(:other_contact) { create(:contact, account: sd_account) }
  let(:unmatched) { sd_ticket(requester: other_contact) }
  let(:parameters) { { customer_segment_id: taxonomy.id } }
  let(:query) { described_class.new(user_context: sd_context, parameters: parameters) }

  before do
    sd_account.enable_features!('jrc_customer_master')
    sd_contact.update!(company_id: company.id)
  end

  it 'keeps native no-filter behavior and filters the same authorized cohort for lists and KPI counts' do
    selected
    unmatched
    create(:jrc_sd_ticket, unit: sd_other_unit, requester: sd_contact)
    native = described_class.new(user_context: sd_context).collection
    expect(native[:items].pluck(:id)).to contain_exactly(selected.id, unmatched.id)
    expect(query.collection[:items].pluck(:id)).to eq([selected.id])
    expect(query.collection[:meta][:total]).to eq(1)
    counts = JrcServiceDesk::DashboardService.new(user_context: sd_context).call(parameters: parameters)
    expect(counts[:total]).to eq(1)
    expect(counts[:active]).to eq(1)
  end

  it 'paginates inside the segment and preserves unit/operator selectors without broadening them' do
    first = selected
    second = sd_ticket
    unmatched
    result = described_class.new(user_context: sd_context, parameters: parameters.merge(
      unit_id: sd_unit.id, operator_company_id: sd_operator.id, page: 2, per_page: 1, sort: 'created_at_asc'
    )).collection
    expect(result[:meta]).to include(total: 2, page: 2, per_page: 1)
    expect(result[:items].pluck(:id)).to eq([second.id])
    expect(result[:items].pluck(:id)).not_to include(first.id, unmatched.id)
  end

  it 'retains explicit contact exclusions even when the customer company matches' do
    selected
    JrcCustomers::SegmentOverride.create!(account: sd_account, taxonomy: taxonomy, contact: sd_contact, mode: 'exclude')
    expect(query.collection[:items]).to be_empty
    expect(query.collection[:meta][:total]).to eq(0)
  end

  it 'rejects foreign or inaccessible units and never treats a segment as an organizational grant' do
    selected
    expect do
      described_class.new(user_context: sd_context, parameters: parameters.merge(unit_id: sd_other_unit.id))
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      described_class.new(user_context: sd_context, parameters: parameters.merge(operator_company_id: sd_foreign_operator.id))
    end.to raise_error(ActiveRecord::RecordNotFound)
    sd_membership.update!(active: false)
    expect { query.collection }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'checks publication and active status for this exact module on every query' do
    taxonomy.update!(modules: ['crm'])
    expect { query.collection }.to raise_error(ActiveRecord::RecordNotFound)
    taxonomy.update!(modules: ['service_desk'], active: false)
    expect { query.collection }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a segment from a different account and malformed or forged selectors' do
    foreign = JrcCustomers::Taxonomy.create!(account: sd_foreign_account, name: 'Foreign service customers', kind: 'segment',
                                             modules: ['service_desk'])
    expect do
      described_class.new(user_context: sd_context, parameters: { customer_segment_id: foreign.id })
    end.to raise_error(ActiveRecord::RecordNotFound)
    [{ customer_segment_id: ['1'] }, { customer_segment_id: '0' }, parameters.merge(user_id: sd_user.id),
     parameters.merge(account_id: sd_foreign_account.id)].each do |input|
      expect { JrcServiceDesk::QueryParameters.new(input) }.to raise_error(ArgumentError)
    end
  end

  it 'requires current directory access only for the extra segment filter' do
    selected
    permissions = JrcServiceDesk::Capabilities::DEFAULTS.fetch('agent').map { |key| "jrc_service_desk_#{key}" }
    role = create(:custom_role, account: sd_account, permissions: permissions)
    sd_account_user.update!(custom_role: role)
    expect(described_class.new(user_context: sd_context).collection[:items].pluck(:id)).to eq([selected.id])
    expect { query.collection }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'also requires the native customer-data capability rather than directory access alone' do
    selected
    permissions = (JrcServiceDesk::Capabilities::DEFAULTS.fetch('agent') - ['customers_view']).map { |key| "jrc_service_desk_#{key}" }
    role = create(:custom_role, account: sd_account, permissions: permissions + ['contact_manage'])
    sd_account_user.update!(custom_role: role)
    expect(described_class.new(user_context: sd_context).collection[:items].pluck(:id)).to eq([selected.id])
    expect { query.collection }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies financial membership without CRM access instead of evaluating hidden amounts as zero' do
    selected
    taxonomy.update!(selection_mode: 'dynamic', criteria: {
                       match: 'all', rules: [{ field: 'active_contract_count', operator: 'less_than', value: '1' }]
                     })
    expect { query.collection }.to raise_error(Pundit::NotAuthorizedError)
  end
end
