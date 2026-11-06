require 'rails_helper'

RSpec.describe 'Native human monitoring alert assessment', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:headers) { actor.create_new_auth_token }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:data) { { health: { score: 20 }, days_without_contact: 1, mrr_cents: 0, _source_ids: {} } }
  let(:processor) { JrcRelationship::Processor.new(context: context, assignment: assignment) }
  let(:action) { processor.action!('health', 'Synthetic monitored cause', data, context.configuration.effective_rules) }
  let(:url) { "#{base}/records/actions/#{action.id}" }
  let(:values) do
    { assignment_id: assignment.id, lock_version: action.lock_version, alert_review_status: 'false_positive',
      alert_review_note: 'Human inspection disproved the current observation' }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists a justified current-cause assessment with server identity and an immutable native audit, without completing the action' do
    original = action.attributes.slice('priority', 'status', 'customer_confirmation', 'source_key', 'factors')
    patch url, headers: headers, as: :json, params: { record: values.merge(actor_id: -1, reviewed_at: '2000-01-01',
                                                                           metadata: { automatic_cause_digest: 'forged' }) }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('alert_review')).to include('status' => 'false_positive', 'actor_id' => actor.id, 'available' => true)
    expect(response.parsed_body.fetch('metadata')).not_to have_key('alert_review')
    expect(action.reload.attributes.slice(*original.keys)).to eq(original)
    expect(action.metadata.fetch('alert_review')).to include('cause_digest' => action.metadata.fetch('automatic_cause_digest'),
                                                             'actor_id' => actor.id)
    get url, headers: headers
    expect(response.parsed_body.fetch('history').first.dig('after',
                                                           'alert_review')).to include('status' => 'false_positive',
                                                                                       'note' => values[:alert_review_note])
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('automatic_alert_review')).to eq('total' => 1, 'confirmed' => 0, 'false_positive' => 1, 'pending' => 0)
  end

  it 'rejects missing reasons and invalid states atomically and does not infer an assessment from dismissal' do
    original = action.attributes.deep_dup
    patch url, headers: headers, as: :json, params: { record: values.merge(alert_review_note: ' ') }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(action.reload.attributes).to eq(original)
    patch url, headers: headers, as: :json, params: { record: values.merge(alert_review_status: 'approved') }
    expect(response).to have_http_status(:unprocessable_entity)
    patch url, headers: headers, as: :json,
               params: { record: { assignment_id: assignment.id, lock_version: action.lock_version, status: 'dismissed' } }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload.metadata).not_to have_key('alert_review')
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('automatic_alert_review')).to include('pending' => 1, 'false_positive' => 0)
  end

  it 'makes an old assessment stale when the actual cause changes and retains the old audited evidence after reassessment' do
    patch url, headers: headers, as: :json, params: { record: values }
    original_review = action.reload.metadata.fetch('alert_review').deep_dup
    processor.action!('health', 'Changed native health observation', data.merge(health: { score: 19 }), context.configuration.effective_rules)
    get url, headers: headers
    expect(response.parsed_body.fetch('alert_review')).to include('status' => 'pending', 'stale' => true)
    expect(response.parsed_body.fetch('alert_review')).not_to have_key('note')
    expect(action.reload.metadata.fetch('alert_review')).to eq(original_review)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('automatic_alert_review')).to include('pending' => 1, 'false_positive' => 0)
    patch url, headers: headers, as: :json,
               params: { record: values.merge(lock_version: action.lock_version, alert_review_status: 'confirmed',
                                              alert_review_note: 'New evidence verified') }
    expect(response).to have_http_status(:ok), response.body
    get url, headers: headers
    reviews = response.parsed_body.fetch('history').filter_map { |event| event.dig('after', 'alert_review', 'status') }
    expect(reviews).to include('confirmed', 'false_positive')
  end

  it 'rejects manual work and stale writes and never accepts a client actor or current cause identifier' do
    manual = JrcRelationship::Workflow.new(context).save(kind: 'actions', attributes: {
                                                           assignment_id: assignment.id, request_id: SecureRandom.uuid, reason: 'Manual follow-up'
                                                         }).fetch(:record)
    patch "#{base}/records/actions/#{manual.id}", headers: headers, as: :json,
                                                  params: { record: values.merge(lock_version: manual.lock_version) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(manual.reload.metadata).not_to have_key('alert_review')
    patch url, headers: headers, as: :json, params: { record: values }
    review = action.reload.metadata.fetch('alert_review').deep_dup
    patch url, headers: headers, as: :json, params: { record: values.merge(lock_version: 0, alert_review_note: 'Stale review') }
    expect(response).to have_http_status(:conflict)
    expect(action.reload.metadata.fetch('alert_review')).to eq(review)
    patch url, headers: headers, as: :json, params: { record: values.merge(lock_version: action.lock_version) }
    expect(action.reload.metadata.fetch('alert_review')).to eq(review)
  end

  it 'requires assessment again when the exact factors or priority change even if the engine cause identifier stays the same' do
    patch url, headers: headers, as: :json, params: { record: values }
    cause = action.reload.metadata.fetch('automatic_cause_digest')
    action.update!(priority: action.priority == 100 ? 99 : 100)
    expect(action.reload.metadata.fetch('automatic_cause_digest')).to eq(cause)
    get url, headers: headers
    expect(response.parsed_body.fetch('alert_review')).to include('status' => 'pending', 'stale' => true)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('automatic_alert_review')).to include('false_positive' => 0, 'pending' => 1)
  end

  it 'uses native portfolio/account permissions for both writes and the filtered summary cohort' do
    action
    analyst = create(:user, account: account, role: :agent)
    analyst_assignment = JrcRelationship::Assignment.create!(account: account, owner: analyst, contact: create(:contact, account: account))
    native = JrcRelationship::Processor.new(context: context, assignment: analyst_assignment)
    own = native.action!('health', 'Other authorized portfolio', data, context.configuration.effective_rules)
    analyst_headers = analyst.create_new_auth_token
    get "#{base}/dashboard", headers: analyst_headers, params: { assignment_id: assignment.id, user_id: actor.id }
    expect(response.parsed_body.fetch('automatic_alert_review')).to include('total' => 0)
    get "#{base}/dashboard", headers: analyst_headers
    expect(response.parsed_body.fetch('automatic_alert_review')).to include('total' => 1, 'pending' => 1)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view])
    account.account_users.find_by!(user: analyst).update!(custom_role: role)
    patch "#{base}/records/actions/#{own.id}", headers: analyst_headers, as: :json,
                                               params: { record: values.merge(assignment_id: analyst_assignment.id, lock_version: own.lock_version) }
    expect(response).to have_http_status(:forbidden)
    foreign = create(:account)
    patch "/api/v1/accounts/#{foreign.id}/relationship/records/actions/#{action.id}", headers: headers, as: :json,
                                                                                      params: { record: values.merge(account_id: account.id) }
    expect(response).to have_http_status(:forbidden)
  end
end
