# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native filters on prospective closure revision candidates', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/closure_revisions" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:source) { lc_publish(definition: lc_definition(tracked: true)).current_version }
  let(:target) { lc_publish(definition: JrcServiceDesk::ClosureRevisionBinding.proposal(source), expected_version: 1).current_version }
  let(:category) { create(:jrc_sd_category, unit: sd_unit) }
  let(:ticket) { sd_ticket(title: 'Synthetic candidate', lifecycle_policy_version: source, category: category, assignee_membership: sd_membership) }
  let(:parameters) { { unit_id: sd_unit.id, source_version_id: source.id, target_version_id: target.id } }

  before { sd_as_admin! }

  it 'uses the authorized native category/status/assignee/text search with consistent counts and no writes' do
    ticket
    sd_ticket(title: 'Different candidate', lifecycle_policy_version: source)
    before = ticket.attributes
    get root, headers: headers,
              params: parameters.merge(filters: { q: 'Synthetic', status_id: sd_status.id, category_id: category.id, assignee_id: sd_account_user.id })
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('items').map { |row| row['id'] }).to eq([ticket.id.to_s])
    expect(response.parsed_body.values_at('total', 'counts')).to eq([1, { 'eligible' => 1 }])
    audits = Audited::Audit.count
    get root, headers: headers, params: parameters.merge(filters: { q: ticket.id.to_s })
    expect(response).to have_http_status(:ok)
    expect(Audited::Audit.count).to eq(audits)
    expect(ticket.reload.attributes).to eq(before)
  end

  it 'rejects a filter catalog from another Account instead of widening the candidate scope' do
    foreign = create(:jrc_sd_category, unit: sd_foreign_unit)
    get root, headers: headers, params: parameters.merge(filters: { category_id: foreign.id })
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects unknown filter keys and malformed dates through the finite native contract' do
    get root, headers: headers, params: parameters.merge(filters: { sql: 'arbitrary' })
    expect(response).to have_http_status(:unprocessable_entity)
    get root, headers: headers, params: parameters.merge(filters: { created_from: 'not-a-date' })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps wildcard characters literal and a real date range within the published source policy' do
    ticket
    get root, headers: headers, params: parameters.merge(filters: { q: '%_' })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get root, headers: headers, params: parameters.merge(filters: { created_from: Date.current.iso8601, created_to: Date.current.iso8601 })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |row| row['id'] }).to eq([ticket.id.to_s])
  end
end
