# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native recorded-call human quality reviews', :pabx do
  include_context 'with native authorized quality review source'

  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/quality_review" }
  let(:headers) { actor.create_new_auth_token }
  let(:snapshot) { JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: record.external_unique_id) }
  let(:values) do
    { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC reviewed summary', 'adjusted_themes' => ['SYNTHETIC followup'],
      'recommendation_ids' => [], 'justification' => 'SYNTHETIC human reason', 'expected_revision' => 0,
      'expected_source_sha256' => snapshot.sha256, 'request_id' => SecureRandom.uuid }
  end

  it 'returns the authorized immutable source with honest missing model/confidence and a real zero quality score' do
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => account.id.to_s, 'recording_id' => record.id.to_s, 'revision' => 0, 'can_review' => true)
    expect(response.parsed_body.fetch('original')).to include('nota_final' => 0, 'model' => nil, 'sentiment_confidence' => nil)
    expect(response.body).not_to include(record.recording_reference, 'SYNTHETIC original transcript', 'synthetic-password')
    expect(response.headers.fetch('Cache-Control')).to include('no-store')
  end

  it 'persists the explicit correction through the authenticated API and reads it again without replacing its source' do
    post path, headers: headers, params: { quality_review: values }, as: :json
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item).to include('origin' => 'human', 'revision' => 1, 'actor_id' => actor.id.to_s)
    get path, headers: headers, as: :json
    expect(response.parsed_body.fetch('latest_review')).to eq(item)
    expect(response.parsed_body.fetch('original').fetch('sentimento_cliente')).to eq('positivo')
    expect(response.parsed_body.fetch('latest_review').fetch('values').fetch('classification')).to eq('negative')
  end

  it 'allows authorized source reading but rejects correction without the independent current review permission' do
    role.update!(permissions: recording_rights)
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('can_review')).to be(false)
    post path, headers: headers, params: { quality_review: values }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'does not infer correction authority from native administrator role or unrelated existing permissions' do
    member.update!(role: :administrator)
    role.update!(permissions: recording_rights)
    post path, headers: headers, params: { quality_review: values }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'rejects foreign accounts and forbids changing the actor or operational scope in the review envelope' do
    foreign = create(:account)
    get path.sub("accounts/#{account.id}", "accounts/#{foreign.id}"), headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post path, headers: headers, params: { quality_review: values.merge('account_id' => foreign.id, 'user_id' => actor.id) }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'rejects malformed envelopes and returns a specific missing-justification error without a partial write' do
    [[{ 'unexpected' => 'SYNTHETIC array' }], 'SYNTHETIC scalar', true].each do |input|
      post path, headers: headers, params: { quality_review: input }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
    end
    post path, headers: headers, params: { quality_review: values.merge('justification' => '') }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('quality_review_justification_required')
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'reports an unavailable native personal recording source without consulting Nico or exposing a provider exception' do
    account.sip_credentials.find_by!(user: actor).update!(enabled: false)
    expect(provider).not_to receive(:find_analysis)
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('error' => 'quality_analysis_source_unavailable')
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'reports absent or unconfigured original analysis without inventing a classification, inference or human revision' do
    [JrcVoiceQuality::ConfigurationError, JrcVoiceQuality::PersistenceError].each do |error|
      allow(provider).to receive(:find_analysis).and_raise(error.new('SYNTHETIC private configuration'))
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'quality_analysis_source_unavailable')
      expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
    end
    allow(provider).to receive(:find_analysis).and_return(nil)
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('quality_analysis_source_unavailable')
    expect(response.parsed_body).not_to have_key('original')
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'returns conflict for a competing revision and retains both the original inference and the accepted history' do
    post path, headers: headers, params: { quality_review: values }, as: :json
    first = response.parsed_body.fetch('item')
    post path, headers: headers, params: { quality_review: values.merge('request_id' => SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('quality_review_revision_changed')
    expect(JrcContactCenter::QualityReviewRevision.where(account: account).pluck(:id)).to eq([first.fetch('id').to_i])
  end

  it 'reads paginated immutable history through current local recording authority even while the remote analysis is unavailable' do
    post path, headers: headers, params: { quality_review: values }, as: :json
    expect(response).to have_http_status(:ok)
    allow(provider).to receive(:find_analysis).and_raise(JrcVoiceQuality::PersistenceError.new('SYNTHETIC unavailable', code: :supabase_error))
    get path + '/history', headers: headers, params: { page: 1, per_page: 1 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'per_page' => 1, 'total' => 1)
    expect(response.parsed_body.fetch('items').sole.fetch('origin')).to eq('human')
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
    get path + '/history', headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not show another historical unit after the native call and current coverage move to a new authorized unit' do
    post path, headers: headers, params: { quality_review: values }, as: :json
    expect(response).to have_http_status(:ok)
    other = account.jrc_crm_business_units.create!(operating_company: company, code: 'B', name: 'SYNTHETIC other business')
    target = JrcContactCenter::Unit.create!(account: account, code: 'B', name: 'SYNTHETIC other unit', kind: 'sac',
                                            settings: { issuer_company_id: company.id, business_unit_id: other.id })
    other_queue = JrcContactCenter::Queue.create!(account: account, unit: target, code: 'B', name: 'SYNTHETIC other queue')
    JrcContactCenter::QueueMembership.create!(account: account, queue: other_queue, account_user: member)
    source_call.update!(current_unit: target, current_queue: other_queue)
    account.jrc_crm_user_business_units.where(user: actor).update_all(active: false)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: other,
                                                active: true, structure_managed: true)
    get path + '/history', headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get path, headers: headers, as: :json
    expect(response.parsed_body).to include('revision' => 1, 'latest_review' => nil)
    expect(response.body).not_to include('SYNTHETIC human reason', 'SYNTHETIC reviewed summary')
  end

  it 'does not use a later authorized recording link to grant access to a different former native call' do
    post path, headers: headers, params: { quality_review: values }, as: :json
    expect(response).to have_http_status(:ok)
    other_call = JrcContactCenter::CallSession.create!(account: account, provider: Pabx::Settings::PROVIDER,
                                                       external_session_id: 'SYNTHETIC-rebound-call', correlation_id: 'SYNTHETIC-rebound-origin',
                                                       current_unit: unit, current_queue: queue, direction: 'inbound', status: 'ended',
                                                       started_at: source_call.started_at, ended_at: source_call.ended_at)
    JrcContactCenter::CallLeg.create!(account: account, call_session: other_call, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'ended', started_at: other_call.started_at, ended_at: other_call.ended_at)
    JrcContactCenter::CallLeg.where(account: account, call_session: source_call).update_all(account_user_id: nil)
    record.update!(external_unique_id: other_call.external_session_id)
    get path + '/history', headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(JrcContactCenter::QualityReviewRevision.where(account: account).count).to eq(1)
    expect(response.body).not_to include('SYNTHETIC human reason', 'SYNTHETIC reviewed summary')
  end
end
