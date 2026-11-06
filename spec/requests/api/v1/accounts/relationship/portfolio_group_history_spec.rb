require 'rails_helper'

RSpec.describe 'Named portfolio operational history', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:writer) { JrcRelationship::PortfolioGroups.new(context) }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic history portfolio') }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/portfolio_groups/#{group.id}" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'projects real native audit events without exposing historical private text or raw customer identifiers' do
    group.update!(objective: 'PRIVATE PRIOR OBJECTIVE')
    writer.update!(group.id, attributes: { objective: 'Current public objective' }, expected_version: 1, reason: 'PRIVATE HUMAN REASON')
    get "#{base}/history", headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('payload').first
    expect(row.keys.sort).to eq(%w[actor at changed_fields id kind reason_recorded])
    expect(row).to include('kind' => 'updated', 'reason_recorded' => true, 'changed_fields' => ['objective'])
    expect(response.body).not_to include('PRIVATE PRIOR OBJECTIVE', 'PRIVATE HUMAN REASON', 'from_value', 'to_value')
    expect(row.fetch('actor')).to include('id' => actor.id, 'name' => actor.name)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'paginates twenty-six actual events and combines kind and native account-timezone period filters' do
    group
    26.times do |index|
      writer.update!(group.id, attributes: { objective: "Synthetic iteration #{index}" },
                               expected_version: index, reason: 'Recorded native history reason')
    end
    get "#{base}/history", headers: headers, params: { page: 2, kind: 'updated' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').size).to eq(1)
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'per_page' => 25, 'total' => 26)
    get "#{base}/history", headers: headers, params: { kind: 'customers' }
    expect(response.parsed_body.fetch('payload')).to eq([])
    get "#{base}/history", headers: headers, params: { from: 3.years.ago.to_date.iso8601, to: 2.years.ago.to_date.iso8601 }
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
  end

  it 'does not include foreign audit rows even if they falsely reference this native group ID' do
    foreign = create(:account)
    JrcCustomers::Audit.record!(account: foreign, actor: nil, resource: group, event_type: 'relationship_updated',
                                metadata: { action: 'portfolio_group_updated' }, to_value: { objective: 'FOREIGN AUDIT VALUE' })
    get "#{base}/history", headers: headers, params: { account_id: foreign.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq([])
    expect(response.body).not_to include('FOREIGN AUDIT VALUE')
  end

  it 'denies read-only group viewers and group managers who cannot see the currently linked native customers' do
    group.update!(visibility: 'account')
    viewer = create(:user, account: account, role: :agent)
    get "#{base}/history", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    customer = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: customer)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    account.account_users.find_by!(user: viewer).update!(custom_role: role)
    group.update!(owner: viewer)
    get "#{base}/history", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'excludes policy events and prevents exports without native configuration or administrator authority' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    viewer = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: viewer).update!(custom_role: role)
    group.update!(owner: viewer)
    configuration = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}")
    JrcCustomers::Audit.record!(account: account, actor: actor, resource: configuration, event_type: 'relationship_updated',
                                metadata: { action: 'configuration_versioned', scope_key: configuration.scope_key })
    get "#{base}/history", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('payload' => [], 'meta' => include('can_read_rules' => false))
    %w[rules restored].each do |kind|
      get "#{base}/history", headers: viewer.create_new_auth_token, params: { kind: kind }
      expect(response).to have_http_status(:forbidden)
    end
    before = JrcCrm::AuditEvent.count
    get "#{base}/export_history", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(JrcCrm::AuditEvent.count).to eq(before)
  end

  it 'exports only the scoped operational projection and records the real export in the native audit store' do
    writer.update!(group.id, attributes: { objective: 'Private audit export value' }, expected_version: 0, reason: 'Private export reason')
    before = JrcCrm::AuditEvent.count
    get "#{base}/export_history", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('version' => 1, 'projection' => 'operational_summary',
                                            'group' => { 'id' => group.id, 'name' => group.name })
    expect(response.parsed_body.fetch('events').size).to eq(1)
    expect(response.body).not_to include('Private audit export value', 'Private export reason', 'from_value', 'to_value')
    expect(JrcCrm::AuditEvent.count).to eq(before + 1)
    expect(JrcCrm::AuditEvent.order(:id).last.metadata.fetch('action')).to eq('portfolio_group_history_exported')
  end

  it 'omits an actor outside the current native roster and historical removed customer identifiers' do
    outsider = create(:user, account: create(:account), role: :administrator)
    JrcCustomers::Audit.record!(account: account, actor: outsider, resource: group, event_type: 'relationship_updated',
                                metadata: { action: 'portfolio_group_customers_updated' },
                                from_value: { customers: [[918_273_645, true]] },
                                to_value: { customers: [], reason: 'Hidden previous customer detail' })
    get "#{base}/history", headers: headers
    row = response.parsed_body.fetch('payload').first
    expect(response).to have_http_status(:ok)
    expect(row).to include('actor' => nil, 'kind' => 'customers', 'changed_fields' => ['customers'], 'reason_recorded' => true)
    expect(response.body).not_to include(outsider.name, '918273645', 'Hidden previous customer detail')
  end

  it 'projects configured rule changes without returning raw rule values and retains archived history' do
    configuration = JrcRelationship::Configuration.create!(account: account, scope_key: "portfolio:#{group.id}")
    JrcCustomers::Audit.record!(account: account, actor: actor, resource: configuration, event_type: 'relationship_updated',
                                metadata: { action: 'configuration_versioned' }, from_value: { rules: {} },
                                to_value: { rules: { portfolio_review_validity_minutes: 9876 }, reason: 'Private configuration reason' })
    group.update!(status: 'archived')
    get "#{base}/history", headers: headers, params: { kind: 'rules' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').first).to include('kind' => 'rules', 'changed_fields' => ['portfolio_review_validity_minutes'])
    expect(response.body).not_to include('9876', 'Private configuration reason')
    get base, headers: headers
    expect(response.parsed_body).to include('can_read_history' => true, 'can_export_history' => true, 'can_configure' => false)
  end
end
