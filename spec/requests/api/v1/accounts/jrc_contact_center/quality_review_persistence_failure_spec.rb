# frozen_string_literal: true

require 'rails_helper'

# A real request outside fixture transactions: the writer must roll back its own PostgreSQL transaction before rendering 503.
RSpec.describe 'Native human quality persistence failure recovery', :pabx do
  self.use_transactional_tests = false
  include_context 'with native authorized quality review source'

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable quality persistence database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  it 'returns a safe persistence error with no partial revision or audit and accepts the exact same explicit retry once' do
    input = persistence_input
    headers = actor.create_new_auth_token
    path = "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/quality_review"
    with_rejected_quality_audit do
      post path, headers: headers, params: { quality_review: input }, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'quality_review_persistence_failed')
    end
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
    expect(quality_audits).to be_empty
    post path, headers: headers, params: { quality_review: input }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account).sole.request_key).to eq(input.fetch('request_id'))
    expect(quality_audits.count).to eq(1)
  end

  def persistence_input
    snapshot = JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: record.external_unique_id)
    { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC private saved draft', 'adjusted_themes' => [],
      'recommendation_ids' => [], 'justification' => 'SYNTHETIC private justification', 'expected_revision' => 0,
      'expected_source_sha256' => snapshot.sha256, 'request_id' => SecureRandom.uuid }
  end

  def quality_audits
    Audited.audit_class.where(associated_type: 'Account', associated_id: account.id, auditable_type: 'JrcContactCenter::QualityReviewRevision')
  end

  def with_rejected_quality_audit
    connection = ApplicationRecord.connection
    name = "cc_synthetic_request_reject_#{Integer(account.id)}"
    condition = "auditable_type <> 'JrcContactCenter::QualityReviewRevision' OR associated_id <> #{Integer(account.id)}"
    connection.add_check_constraint(:audits, condition, name: name)
    installed = true
    yield
  ensure
    connection.remove_check_constraint(:audits, name: name) if installed
  end
end
