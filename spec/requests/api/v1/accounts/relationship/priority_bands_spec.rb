require 'rails_helper'

RSpec.describe 'Native configured relationship priority bands', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:headers) { actor.create_new_auth_token }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:bands) { %w[P0 P1 P2 P3].zip([90, 80, 60, 0]).map { |code, minimum| { 'code' => code, 'minimum' => minimum } } }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { 'priority_bands' => bands }) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/records/actions" }
  let(:config_url) { "/api/v1/accounts/#{account.id}/relationship/configuration" }
  let(:action) do
    configuration
    JrcRelationship::Workflow.new(context).save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
                                                                               reason: 'Explicit native review', priority: 88 }).fetch(:record)
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'captures the actual current policy through native create and manual edit, retaining optimistic concurrency and source permissions' do
    post url, headers: headers, as: :json, params: { record: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
                                                               reason: 'A scoped manual action', priority: 88 } }
    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body['factors']).not_to have_key('priority_band')
    row = JrcRelationship::Action.find(response.parsed_body.fetch('id'))
    configuration
    patch "#{url}/#{row.id}", headers: headers, as: :json,
                              params: { record: { assignment_id: assignment.id, lock_version: row.lock_version, priority: 95 } }
    expect(response).to have_http_status(:ok), response.body
    expect(row.reload.factors).to include('priority_band' => 'P0', 'priority_band_score' => 95)
    patch "#{url}/#{row.id}", headers: headers, as: :json,
                              params: { record: { assignment_id: assignment.id, lock_version: 0, priority: 80 } }
    expect(response).to have_http_status(:conflict)
    expect(row.reload.priority).to eq(95)
  end

  it 'retains the captured policy during unrelated edits and native system escalation after the default changes' do
    original = action.factors.deep_dup
    configuration.update!(rules: { 'priority_bands' => [] })
    action.update!(reason: 'Unrelated edit')
    expect(action.reload.factors).to eq(original)
    action.update!(priority: 100)
    expect(action.reload.factors).to include('priority_band' => 'P0', 'priority_band_score' => 100,
                                             'priority_band_policy' => original.fetch('priority_band_policy'))
    values = { assignment_id: assignment.id, lock_version: action.lock_version, priority: 100 }
    JrcRelationship::Workflow.new(JrcRelationship::Context.new(member)).save(kind: 'actions', id: action.id, attributes: values)
    expect(action.reload.factors).to include('priority_band_policy' => original.fetch('priority_band_policy'), 'priority_band_score' => 100)
    values[:lock_version] = action.lock_version
    values[:priority] = 99
    JrcRelationship::Workflow.new(JrcRelationship::Context.new(member)).save(kind: 'actions', id: action.id, attributes: values)
    expect(action.reload.factors.keys.grep(/priority_band/)).to eq([])
  end

  it 'does not replace pinned evidence when the native editor resubmits an unchanged score after a configuration publication' do
    original_factors = action.factors.deep_dup
    original_metadata = action.metadata.deep_dup
    original_source = action.source_key
    get config_url, headers: headers
    change = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    replacement = %w[P0 P1 P2 P3].zip([95, 90, 70, 0]).map { |code, minimum| { 'code' => code, 'minimum' => minimum } }
    change['rules']['priority_bands'] = replacement
    patch config_url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:ok), response.body
    configuration_history = response.parsed_body.fetch('history').deep_dup

    patch "#{url}/#{action.id}", headers: headers, as: :json,
                                 params: { record: { assignment_id: assignment.id, lock_version: action.lock_version,
                                                     reason: 'Only the operational reason changed', priority: '88', status: action.status } }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload.factors).to eq(original_factors)
    expect(action.attributes).to include('metadata' => original_metadata, 'source_key' => original_source,
                                         'reason' => 'Only the operational reason changed')

    patch "#{url}/#{action.id}", headers: headers, as: :json,
                                 params: { record: { assignment_id: assignment.id, lock_version: action.lock_version, priority: 89 } }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload.factors).to include('priority_band' => 'P2', 'priority_band_score' => 89, 'priority_band_policy' => replacement.to_json)
    get config_url, headers: headers
    expect(response.parsed_body.fetch('history')).to eq(configuration_history)
  end

  it 'feeds the native calculation, CRM activity and playbook action constructors rather than only rendering a visual badge' do
    configuration
    data = { health: { score: 10 }, mrr_cents: 0, renewal_on: Date.current + 120, days_without_contact: 0 }
    generated = JrcRelationship::Processor.new(context: context, assignment: assignment).action!('health', 'Observed risk', data,
                                                                                                 configuration.effective_rules)
    expect(generated.reload.factors).to include('priority_band' => 'P0', 'priority_band_score' => generated.priority)
    native = JrcRelationship::Workflow.new(context).activity!(assignment: assignment, title: 'Real internal agenda projection',
                                                              due_at: 1.day.from_now, request_id: SecureRandom.uuid)
    expect(JrcRelationship::Action.find_by!(activity: native).factors).to include('priority_band' => 'P3', 'priority_band_score' => 50)
    book = JrcRelationship::Playbook.create!(account: account, name: 'Native priority action', trigger_kind: 'no_contact',
                                             steps: [{ 'kind' => 'action', 'title' => 'Native playbook work', 'after_days' => 0 }])
    JrcRelationship::Playbooks.new(context).run!(assignment, 'no_contact', playbook_id: book.id, source_key: SecureRandom.uuid)
    expect(assignment.actions.where("source_key LIKE 'playbook:%'").sole.factors).to include('priority_band' => 'P3')
  end

  it 'versions explicit limits without rewriting old configuration versions and rejects stale or malformed writes' do
    get config_url, headers: headers
    original = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    change = original.deep_dup
    change['rules']['priority_bands'] = bands
    patch config_url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:ok), response.body
    history = response.parsed_body.fetch('history')
    expect(history.first.dig('rules', 'priority_bands')).to eq(bands)
    expect(history.last.fetch('rules')).not_to have_key('priority_bands')
    patch config_url, headers: headers, as: :json, params: original
    expect(response).to have_http_status(:conflict)
    get config_url, headers: headers
    current = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    current['rules']['priority_bands'][0]['minimum'] = 79
    patch config_url, headers: headers, as: :json, params: current
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'paginates the actual filtered queue, clears the filter, excludes legacy labels and rejects foreign account access' do
    configuration
    26.times do |index|
      JrcRelationship::Workflow.new(context).save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
                                                                                 reason: "Scoped queue #{index}", priority: 90 })
    end
    JrcRelationship::Workflow.new(context).save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: SecureRandom.uuid,
                                                                               reason: 'Different band', priority: 70 })
    get url, headers: headers, params: { priority_band: 'P0', page: 2, per_page: 25 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('meta')).to include('total' => 26, 'page' => 2)
    expect(response.parsed_body.fetch('payload').size).to eq(1)
    get url, headers: headers
    expect(response.parsed_body.dig('meta', 'total')).to eq(27)
    get url, headers: headers, params: { priority_band: 'P4' }
    expect(response).to have_http_status(:unprocessable_entity)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/records/actions", headers: headers, params: { priority_band: 'P0', account_id: account.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'never grants configuration or another owner’s queue to a restricted native analyst through a band or supplied account parameters' do
    action
    analyst = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    analyst_headers = analyst.create_new_auth_token
    get url, headers: analyst_headers, params: { priority_band: 'P1', owner_id: actor.id, user_id: actor.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    patch config_url, headers: analyst_headers, as: :json, params: { version: configuration.version, rules: { priority_bands: bands } }
    expect(response).to have_http_status(:forbidden)
  end
end
