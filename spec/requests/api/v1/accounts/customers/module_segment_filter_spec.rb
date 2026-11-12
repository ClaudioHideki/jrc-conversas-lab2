require 'rails_helper'

RSpec.describe 'Published customer segments in CRM views', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}" }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'CRM published', kind: 'segment', modules: ['crm']) }
  let(:company) { account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:person) { create(:contact, account: account, company_id: company.id) }
  let(:other) { create(:contact, account: account) }
  let!(:lead) { account.jrc_crm_leads.create!(name: 'Selected lead', owner: actor, contact: person) }
  let!(:unmatched) { account.jrc_crm_leads.create!(name: 'Unmatched lead', owner: actor, contact: other) }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'preserves the native response without a filter and narrows the selected view without modifying records' do
    get "#{root}/crm/leads", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to contain_exactly(lead.id, unmatched.id)
    before = [lead.reload.attributes, unmatched.reload.attributes]
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to eq([lead.id])
    expect([lead.reload.attributes, unmatched.reload.attributes]).to eq(before)
  end

  it 'does not apply a list filter to showing or updating a native permitted record' do
    get "#{root}/crm/leads/#{unmatched.id}", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(unmatched.id)
    patch "#{root}/crm/leads/#{unmatched.id}", headers: headers,
                                               params: { customer_segment_id: taxonomy.id, lead: { name: 'Native update retained' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(unmatched.reload.name).to eq('Native update retained')
  end

  it 'retains ownership and organizational scope even when a foreign owner shares the selected customer' do
    other_actor = create(:user, account: account, role: :agent)
    hidden = account.jrc_crm_leads.create!(name: 'Hidden owner lead', owner: other_actor, contact: person)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: taxonomy.id, user_id: other_actor.id, unit_id: 0 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to eq([lead.id])
    expect(response.parsed_body.pluck('id')).not_to include(hidden.id)
  end

  it 'applies the same filter to the native activity list while preserving its array response' do
    selected = account.jrc_crm_activities.create!(user: actor, lead: lead, title: 'Selected activity', activity_type: 'task')
    account.jrc_crm_activities.create!(user: actor, lead: unmatched, title: 'Unmatched activity', activity_type: 'task')
    get "#{root}/crm/activities", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to eq([selected.id])
  end

  it 'accepts the optional filter in remaining connected CRM lists without changing their empty response contract' do
    %w[deals proposals sales_orders contracts].each do |resource|
      get "#{root}/crm/#{resource}", headers: headers, params: { customer_segment_id: taxonomy.id }
      expect(response).to have_http_status(:ok), "#{resource}:#{response.status}"
      expect(response.parsed_body).to eq([])
    end
  end

  it 'matches canonical links and uses only an authorized deal for legacy proposals without direct customer links' do
    pipeline = create(:jrc_crm_pipeline, account: account)
    stage = create(:jrc_crm_stage, account: account, pipeline: pipeline)
    deal = create(:jrc_crm_deal, account: account, owner: actor, contact: person, pipeline: pipeline, stage: stage)
    proposal = create(:jrc_crm_proposal, account: account, owner: actor, deal: deal, contact: nil, company: nil)
    order = account.jrc_crm_sales_orders.create!(owner: actor, contact: person, source_type: 'manual', order_origin: 'direct_sale',
                                                 status: 'invoiced')
    contract = account.jrc_crm_contracts.create!(owner: actor, contact: person, sales_order: order)
    { 'deals' => deal, 'proposals' => proposal, 'sales_orders' => order, 'contracts' => contract }.each do |resource, record|
      get "#{root}/crm/#{resource}", headers: headers, params: { customer_segment_id: taxonomy.id }
      expect(response).to have_http_status(:ok), "#{resource}:#{response.status}"
      expect(response.parsed_body.pluck('id')).to eq([record.id])
    end
    account.account_users.find_by!(user: actor).update!(role: :agent)
    deal.update!(owner: create(:user, account: account, role: :agent))
    get "#{root}/crm/proposals", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq([])
  end

  it 'rejects unpublished, inactive and foreign segments without granting access or guessing another account' do
    taxonomy.update!(modules: ['service_desk'])
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
    taxonomy.update!(modules: ['crm'], active: false)
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master')
    create(:account_user, account: foreign, user: actor, role: :administrator)
    foreign_segment = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign', kind: 'segment', modules: ['crm'])
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: foreign_segment.id, account_id: foreign.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'requires directory permission for the extra filter and preserves native CRM operation when the filter is absent' do
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    get "#{root}/crm/leads", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:unauthorized)
    role.update!(permissions: ['contact_manage'])
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'publishes only the selected module catalog while preserving the complete Master catalog and totals' do
    sd = JrcCustomers::Taxonomy.create!(account: account, name: 'SD published', kind: 'segment', modules: ['service_desk'])
    draft = JrcCustomers::Taxonomy.create!(account: account, name: 'Master only', kind: 'segment', modules: [])
    get "#{root}/customers/taxonomies", headers: headers, params: { module_key: 'crm', per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([taxonomy.id])
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(1)
    get "#{root}/customers/taxonomies", headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to contain_exactly(taxonomy.id, sd.id, draft.id)
    get "#{root}/customers/taxonomies", headers: headers, params: { module_key: 'unsupported' }
    expect(response).to have_http_status(:bad_request)
  end

  it 'previews and persists explicit invoiced periods without exposing financial amounts in membership payloads' do
    account.jrc_crm_sales_orders.create!(owner: actor, contact: person, source_type: 'manual', order_origin: 'direct_sale',
                                         status: 'invoiced', total_cents: 12_345, sold_at: '2026-10-15T12:00:00Z')
    attributes = { kind: 'segment', name: 'October invoices', selection_mode: 'dynamic', modules: ['crm'],
                   criteria: { match: 'all', rules: [{ field: 'invoiced_revenue', operator: 'at_least', value: '123.45',
                                                       period_start: '2026-10-01', period_end: '2026-10-31' }] } }
    post "#{root}/customers/taxonomies/preview", headers: headers, params: { taxonomy: attributes }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([company.id])
    expect(response.parsed_body.fetch('payload').first.keys).not_to include('total_cents', 'invoiced_revenue', 'bank_account')
    post "#{root}/customers/taxonomies", headers: headers, params: { taxonomy: attributes }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('payload').fetch('id')
    expect(JrcCustomers::Taxonomy.find(id).criteria).to eq(attributes[:criteria].deep_stringify_keys)
    get "#{root}/crm/leads", headers: headers, params: { customer_segment_id: id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to eq([lead.id])
  end

  it 'rejects incomplete financial definitions and denies financial membership after CRM access is revoked' do
    rule = { field: 'invoiced_revenue', operator: 'less_than', value: '100' }
    attributes = { kind: 'segment', name: 'Billing restricted', selection_mode: 'dynamic', criteria: { match: 'all', rules: [rule] } }
    post "#{root}/customers/taxonomies", headers: headers, params: { taxonomy: attributes }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    rule[:period_start] = '2026-10-01'
    rule[:period_end] = '2026-10-31'
    post "#{root}/customers/taxonomies", headers: headers, params: { taxonomy: attributes }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('payload').fetch('id')
    account.disable_features!('jrc_crm')
    get "#{root}/customers/taxonomies/#{id}/members", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
