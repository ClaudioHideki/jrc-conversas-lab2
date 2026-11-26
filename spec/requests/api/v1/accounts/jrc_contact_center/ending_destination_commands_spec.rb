# frozen_string_literal: true

require 'rails_helper'

# Real authenticated requests and committed native PostgreSQL rows. Delivery
# uses this job's test adapter; the independent owned-worker suite proves Redis
# dequeue. Neither this preparation nor an HTTP 202 proves a native effect.
RSpec.describe 'Selected original-agent ending destination commands', type: :request do
  self.use_transactional_tests = false
  include_context 'with native typed ending schema evidence'

  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{qualification.id}/ending_destinations" }
  let(:typed_version) { publish_typed_schema_definition('timing' => 'call_end') }
  let(:typed_origin) do
    original = origin
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
      qualification, attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
    )
    original.reload
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned committed destination-command database required' unless owned && !ApplicationRecord.connection.transaction_open?

    job = JrcContactCenter::EndingDestinationJob
    previous = job._test_adapter
    job.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    job&.enable_test_adapter(previous)
  end

  before { typed_origin }

  def root_review
    context = typed_context
    { confirmed: true, expected_readiness_id: context.fetch('readiness_id').to_s,
      expected_version_id: context.fetch('version_id').to_s, expected_rule_sha256: context.fetch('rule_sha256') }
  end

  def input
    { origin_id: typed_origin.id.to_s, rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task',
      request_key: typed_key, review: root_review }
  end

  def selected_review(row)
    { confirmed: true, expected_readiness_id: row.readiness_id.to_s, expected_version_id: row.version_id.to_s,
      expected_rule_sha256: row.rule_sha256, expected_request_id: row.request_key }
  end

  def counts
    [JrcContactCenter::EndingDestinationConsent.where(account: account).count,
     JrcContactCenter::EndingDestinationAttempt.where(account: account).count,
     JrcProjects::Task.where(account: account).count]
  end

  def recorded_root
    post endpoint, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:accepted)
    JrcContactCenter::EndingDestinationAttempt.where(account: account).sole
  end

  it 'lists only eligible immutable action metadata without consenting, queuing, completing ACW or executing a destination' do
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    row = response.parsed_body.fetch('items').sole
    expect(row.keys).to match_array(%w[origin_id readiness_id version_id rule_code destination_kind operation rule_sha256])
    expect(row).to include('origin_id' => typed_origin.id.to_s, 'destination_kind' => 'project_task')
    expect(response.body).not_to include('SYNTHETIC unarmed original evidence', 'board_column_id', 'actor_user_id')
    expect(counts).to eq([0, 0, 0])
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingDestinationJob.queue_adapter.enqueued_jobs).to be_empty
  end

  it 'registers distinct action consent and a durable intent through the real API while native ACW remains open' do
    row = recorded_root
    expect(response.parsed_body).to include(
      'contract_version' => 1, 'account_id' => account.id.to_s, 'qualification_id' => qualification.id.to_s,
      'ledger' => 'typed', 'attempt_id' => row.id.to_s, 'request_id' => typed_key,
      'status' => 'accepted', 'execution_confirmed' => false
    )
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(counts).to eq([1, 1, 0])
    expect(qualification.reload.completed_at).to be_nil
    expect(row.outcome).to be_nil
    expect(row.consent.actor_account_user_id).to eq(member.id)
  end

  it 'replays an uncertain root request without minting a second consent, intent or native task' do
    first = recorded_root
    post endpoint, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch('attempt_id')).to eq(first.id.to_s)
    expect(counts).to eq([1, 1, 0])
  end

  it 'rejects a second root UUID rather than recording an orphan consent or repeating the selected action' do
    recorded_root
    post endpoint, headers: headers, params: input.merge(request_key: SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:conflict)
    expect(counts).to eq([1, 1, 0])
  end

  it 'requires action confirmation even though classification was already explicitly confirmed' do
    post endpoint, headers: headers, params: input.merge(review: root_review.merge(confirmed: false)), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(counts).to eq([0, 0, 0])
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'rejects extra actor or account identifiers rather than treating request data as authority' do
    post endpoint, headers: headers, params: input.merge(account_id: account.id.to_s, user_id: actor.id.to_s), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(counts).to eq([0, 0, 0])
  end

  it 'requires JSON without dropping a rejected original-agent draft or completing ACW' do
    post endpoint, headers: headers, params: input
    expect(response).to have_http_status(:unprocessable_entity)
    expect(counts).to eq([0, 0, 0])
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'rejects a stale reviewed rule before recording consent or an attempt' do
    review = root_review.merge(expected_rule_sha256: '0' * 64)
    post endpoint, headers: headers, params: input.merge(review: review), as: :json
    expect(response).to have_http_status(:conflict)
    expect(counts).to eq([0, 0, 0])
  end

  it 'does not admit a foreign account credential or expose the original rule configuration' do
    foreign = create(:account)
    outsider = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    post endpoint, headers: outsider.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_ORIGIN_RULE')
    expect(counts).to eq([0, 0, 0])
  end

  it 'does not let a second native administrator impersonate the original agent action consent' do
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    post endpoint, headers: other.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(counts).to eq([0, 0, 0])
  end

  it 'revalidates current operating eligibility after a valid preview and before the authenticated write' do
    body = input
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(counts).to eq([0, 0, 0])
  end

  it 'does not reuse earlier corporate coverage after that original operating scope has been withdrawn' do
    body = input
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, active: true).find_each { |coverage| coverage.update!(active: false) }
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:not_found)
    expect(counts).to eq([0, 0, 0])
  end

  it 'resumes only the same reviewed pending intent without creating a retry, consent or synchronous native effect' do
    row = recorded_root
    post "#{endpoint}/#{row.id}/resume", headers: headers, params: { review: selected_review(row) }, as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch('attempt_id')).to eq(row.id.to_s)
    expect(response.parsed_body.fetch('execution_confirmed')).to be(false)
    expect(counts).to eq([1, 1, 0])
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'records exactly one explicit selected retry with its own action consent and preserved native effect identity' do
    row = recorded_root
    JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row, outcome: 'failed', result_code: 'destination_failure')
    body = { request_key: SecureRandom.uuid, review: selected_review(row) }
    2.times do
      post "#{endpoint}/#{row.id}/retry", headers: headers, params: body, as: :json
      expect(response).to have_http_status(:accepted)
    end
    child = JrcContactCenter::EndingDestinationAttempt.where(account: account, retry_of_id: row.id).sole
    expect(child.effect_key).to eq(row.effect_key)
    expect(child.consent_id).not_to eq(row.consent_id)
    expect(counts).to eq([2, 2, 0])
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'does not reinterpret a still-pending destination as a failed attempt eligible for a new retry' do
    row = recorded_root
    post "#{endpoint}/#{row.id}/retry", headers: headers,
                                       params: { request_key: SecureRandom.uuid, review: selected_review(row) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(counts).to eq([1, 1, 0])
  end

  it 'does not retry a real succeeded native task or grant permission based on its immutable success receipt' do
    row = recorded_root
    result = JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: row.id).call
    expect(result.outcome).to eq('succeeded')
    post "#{endpoint}/#{row.id}/retry", headers: headers,
                                       params: { request_key: SecureRandom.uuid, review: selected_review(row) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(counts).to eq([1, 1, 1])
    expect(qualification.reload.completed_at).to be_nil
  end
end
