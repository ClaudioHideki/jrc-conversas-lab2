require 'rails_helper'

RSpec.describe 'Operational portfolio link results and fresh review', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic reviewed group') }
  let(:first) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:second) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/portfolio_groups/#{group.id}" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'returns committed per-customer results and identifies idempotent retries without incrementing revisions' do
    group.customer_links.create!(account: account, assignment: first)
    ids = [first.id, second.id]
    bodies = []
    [[true, 0], [true, 1], [false, 1], [false, 2]].each do |active, revision|
      patch "#{base}/customers", headers: headers, as: :json, params: {
        assignment_ids: ids, active: active, expected_version: revision, reason: 'Explicit native link review'
      }
      expect(response).to have_http_status(:ok)
      bodies << response.parsed_body
    end
    expect(bodies.pluck('version')).to eq([1, 1, 2, 2])
    expect(bodies.map { |body| body.fetch('results').pluck('assignment_id') }).to eq([ids] * 4)
    expect(bodies.map { |body| body.fetch('results').pluck('state') })
      .to eq([%w[already_linked linked], %w[already_linked already_linked], %w[unlinked unlinked], %w[already_unlinked already_unlinked]])
    expect(group.customer_links.where(active: true).count).to eq(0)
  end

  it 'reloads only the selected current subjects and current group revision without writing anything' do
    group.customer_links.create!(account: account, assignment: first)
    group.update!(objective: 'A changed native grouping')
    second
    before = [JrcCrm::AuditEvent.count, group.customer_links.count]
    post "#{base}/customer_review", headers: headers, as: :json, params: { assignment_ids: [second.id, first.id] }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('group' => { 'id' => group.id, 'version' => 1 })
    expect(response.parsed_body.fetch('payload')).to eq([
                                                          { 'id' => first.id, 'name' => first.label,
                                                            'linked' => true }, { 'id' => second.id, 'name' => second.label, 'linked' => false }
                                                        ])
    expect([JrcCrm::AuditEvent.count, group.customer_links.count]).to eq(before)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'requires a newly confirmed revision after a real conflict and preserves the rejected link state' do
    group.update!(objective: 'Changed by a separate operation')
    patch "#{base}/customers", headers: headers, as: :json, params: {
      assignment_ids: [first.id], active: true, expected_version: 0, reason: 'Draft reason remains with the operator'
    }
    expect(response).to have_http_status(:conflict)
    expect(group.customer_links.count).to eq(0)
    post "#{base}/customer_review", headers: headers, as: :json, params: { assignment_ids: [first.id] }
    revision = response.parsed_body.fetch('group').fetch('version')
    patch "#{base}/customers", headers: headers, as: :json, params: {
      assignment_ids: [first.id], active: true, expected_version: revision, reason: 'New explicit confirmation'
    }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('version' => 2, 'results' => [{ 'assignment_id' => first.id, 'state' => 'linked' }])
  end

  it 'does not include foreign or currently hidden subjects in the re-review payload' do
    foreign = create(:account)
    outsider = create(:user, account: foreign, role: :administrator)
    hidden = JrcRelationship::Assignment.create!(account: foreign, owner: outsider, contact: create(:contact, account: foreign))
    post "#{base}/customer_review", headers: headers, as: :json, params: { assignment_ids: [first.id, hidden.id] }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('payload')
    role = account.custom_roles.create!(name: 'Synthetic scoped supervisor',
                                        permissions: %w[contact_manage jrc_relationship_view
                                                        jrc_relationship_manage jrc_relationship_team])
    supervisor = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: supervisor).update!(custom_role: role)
    group.update!(owner: supervisor)
    post "#{base}/customer_review", headers: supervisor.create_new_auth_token, as: :json, params: { assignment_ids: [first.id] }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('payload')
  end

  it 'rejects malformed or excessive selections and archived groups before exposing subject data' do
    [[first.id, first.id], [], [nil], [first.id] * 51, { id: first.id }].each do |ids|
      post "#{base}/customer_review", headers: headers, as: :json, params: { assignment_ids: ids }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    group.update!(status: 'archived')
    post "#{base}/customer_review", headers: headers, as: :json, params: { assignment_ids: [first.id] }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(group.customer_links.count).to eq(0)
  end

  it 'rolls back the complete link request when a later selected customer violates the native unit rule' do
    operator = account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(operating_company: operator, name: 'Synthetic source unit', code: SecureRandom.hex(6))
    other_unit = account.jrc_crm_business_units.create!(operating_company: operator, name: 'Synthetic other unit', code: SecureRandom.hex(6))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'COMPANY', company: operator, active: true, structure_managed: true)
    group.update!(business_unit: unit)
    first.update!(business_unit: unit)
    second.update!(business_unit: other_unit)
    ids = [first.id, second.id]
    before = JrcCrm::AuditEvent.count
    patch "#{base}/customers", headers: headers, as: :json, params: {
      assignment_ids: ids, active: true, expected_version: 1, reason: 'Atomic reviewed batch, later unit mismatch'
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).not_to have_key('results')
    expect([group.customer_links.count, group.reload.lock_version, JrcCrm::AuditEvent.count]).to eq([0, 1, before])
  end
end
