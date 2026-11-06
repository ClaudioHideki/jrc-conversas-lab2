require 'rails_helper'

RSpec.describe 'Native supervised analyst cadence controls', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, account: account, role: :administrator) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:source_member) { account.account_users.find_by!(user: operator) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: contact, owner: operator) }
  let(:book) do
    JrcRelationship::Playbook.create!(account: account, name: 'Private original schedule', active: true, trigger_kind: 'no_contact',
                                      steps: [{ 'kind' => 'activity', 'title' => 'Original applied task', 'after_days' => 0 },
                                              { 'kind' => 'meeting', 'title' => 'Private original next step', 'after_days' => 2 }])
  end
  let(:review) do
    service = JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(source_member))
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    service.advance(preview.fetch('id'))
    JrcRelationship::BatchReview.find(preview.fetch('id'))
  end
  let(:inputs) do
    { 'ids' => [assignment.id], 'operation' => 'cadence', 'playbook_id' => book.id,
      'conversation_id' => conversation.display_id, 'starts_at' => Time.current.iso8601(6), 'request_id' => SecureRandom.uuid }
  end
  let(:cadence) { JrcRelationship::CadenceEnrollment.find_by!(batch_review: review) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/team/#{operator.id}/cadences" }
  let(:headers) { manager.create_new_auth_token }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'lists the current native customer, revision and real pending work without disclosing original source contents' do
    cadence
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body['payload']).to include(include('id' => cadence.id, 'revision' => 1, 'pending_steps' => 2,
                                                               'customer_name' => assignment.label))
    expect(response.parsed_body['meta']).to include('page' => 1, 'per_page' => 10, 'total' => 1)
    expect(response.body).not_to include(book.name, 'Private original next step', 'snapshot', 'receipt', 'conversation_id')
    get url, headers: headers, params: { page: 2 }
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'stops only pending native steps after a reviewed revision while preserving original actor, applied receipts and frozen snapshots' do
    JrcRelationship::ReviewedCadence.new(JrcRelationship::Context.new(source_member)).advance(cadence.id)
    original = cadence.reload.attributes.slice('actor_id', 'snapshot', 'batch_review_id', 'conversation_id', 'starts_at')
    applied = cadence.steps.find_by!(state: 'applied').attributes.deep_dup
    frozen = review.reload.snapshot.deep_dup
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json,
                                        params: { expected_revision: cadence.revision, reason: 'Reviewed; remaining work is no longer appropriate.' }
    expect(response).to have_http_status(:ok), response.body
    expect(cadence.reload).to have_attributes(state: 'stopped', stop_reason: 'CANCELED_BY_SUPERVISOR')
    expect(cadence.steps.order(:ordinal).pluck(:state)).to eq(%w[applied canceled])
    expect([cadence.attributes.slice(*original.keys), cadence.steps.find_by!(state: 'applied').attributes, review.reload.snapshot])
      .to eq([original, applied, frozen])
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: cadence.class.name, resource_id: cadence.id, actor_id: manager.id)
                            .where("metadata ->> 'action' = 'cadence_stopped_by_team'")).to exist
  end

  it 'requires a current revision and explicit reason, and never records a false second stop' do
    cadence
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json, params: { expected_revision: cadence.revision + 1, reason: 'Stale review' }
    expect(response).to have_http_status(:conflict)
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json, params: { expected_revision: cadence.revision, reason: ' ' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(cadence.reload).to have_attributes(state: 'active', revision: 1)
    expect(cadence.steps.pluck(:state)).to eq(%w[pending pending])
  end

  it 'does not require impersonating an original operator whose relationship access has been revoked' do
    cadence
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    source_member.update!(role: :agent, custom_role: role)
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json,
                                        params: { expected_revision: cadence.revision, reason: 'Explicit supervisor decision' }
    expect(response).to have_http_status(:ok), response.body
    expect(cadence.reload.actor_id).to eq(operator.id)
    expect(cadence.state).to eq('stopped')
  end

  it 'denies ordinary analysts and foreign-account routes without leaking original schedule details or stopping work' do
    cadence
    account.account_users.find_by!(user: manager).update!(role: :agent)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json, params: { expected_revision: cadence.revision, reason: 'Denied request' }
    expect(response).to have_http_status(:forbidden)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/team/#{operator.id}/cadences", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(cadence.reload.state).to eq('active')
  end

  it 'denies team-role counts before disclosure when the native private portfolio is outside the reviewers scope' do
    cadence
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    account.account_users.find_by!(user: manager).update!(role: :agent, custom_role: role)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(book.name, assignment.label, 'pending_steps', 'total')
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json, params: { expected_revision: cadence.revision, reason: 'Denied private source' }
    expect(response).to have_http_status(:not_found)
    expect(cadence.reload.state).to eq('active')
  end

  it 'paginates real native enrollments and retains the original full-detail actor boundary' do
    cadence
    10.times do
      service = JrcRelationship::ReviewedPortfolioBatch.new(JrcRelationship::Context.new(source_member))
      preview = service.preview(inputs.merge('request_id' => SecureRandom.uuid))
      service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
      service.advance(preview.fetch('id'))
    end
    get url, headers: headers
    first = response.parsed_body
    get url, headers: headers, params: { page: 2 }
    last = response.parsed_body
    expect([first['payload'].size, last['payload'].size, last.dig('meta', 'total')]).to eq([10, 1, 11])
    expect((first['payload'] + last['payload']).pluck('id').uniq.size).to eq(11)
    get "/api/v1/accounts/#{account.id}/relationship/cadences/#{cadence.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    target = "/api/v1/accounts/#{account.id}/relationship/team/#{manager.id}/cadences/#{cadence.id}/cancel"
    post target, headers: headers, as: :json, params: { expected_revision: cadence.revision, reason: 'Mismatched original operator' }
    expect(response).to have_http_status(:not_found)
  end

  it 'allows scoped team readers to inspect work while denying the actual stop without native manage permission' do
    cadence
    team = create(:team, account: account)
    create(:team_member, team: team, user: manager)
    assignment.update!(team: team)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team])
    account.account_users.find_by!(user: manager).update!(role: :agent, custom_role: role)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('can_stop' => false)
    expect(response.parsed_body['payload'].pluck('id')).to eq([cadence.id])
    post "#{url}/#{cadence.id}/cancel", headers: headers, as: :json,
                                        params: { expected_revision: cadence.revision, reason: 'Read permission cannot grant stop authority' }
    expect(response).to have_http_status(:forbidden)
    expect(cadence.reload.state).to eq('active')
  end

  it 'includes active portfolio dependencies even when another operator owns the original cadence execution' do
    cadence
    assignment.update!(owner: manager)
    portfolio_url = "/api/v1/accounts/#{account.id}/relationship/team/#{manager.id}/cadences"
    get portfolio_url, headers: headers
    expect(response.parsed_body['payload']).to include(include('id' => cadence.id, 'responsibility' => 'portfolio_owner'))
    get "/api/v1/accounts/#{account.id}/relationship/team/#{manager.id}/withdrawal_readiness", headers: headers
    expect(response.parsed_body.fetch('counts')).to include('cadences' => 1, 'allocations' => 1)
    get url, headers: headers
    expect(response.parsed_body['payload']).to include(include('id' => cadence.id, 'responsibility' => 'execution_actor'))
    post "#{portfolio_url}/#{cadence.id}/cancel", headers: headers, as: :json,
                                                  params: { expected_revision: cadence.revision, reason: 'Reviewed portfolio dependency.' }
    expect(response).to have_http_status(:ok), response.body
    expect(cadence.reload).to have_attributes(state: 'stopped', actor_id: operator.id)
    get "/api/v1/accounts/#{account.id}/relationship/team/#{manager.id}/withdrawal_readiness", headers: headers
    expect(response.parsed_body.fetch('counts')).to include('cadences' => 0, 'allocations' => 1)
  end
end
