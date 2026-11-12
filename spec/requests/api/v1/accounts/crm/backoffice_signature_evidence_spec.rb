require 'rails_helper'

RSpec.describe 'Backoffice signature evidence API', :approval_core, :authority_core, :signature_delivery_core, type: :request do
  self.use_transactional_tests = false
  let(:domain) { admitted_signature_domain }
  let(:account) { domain.fetch(:account) }
  let(:actor) { domain.fetch(:actor) }
  let(:delivery) { domain.fetch(:delivery) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}/contract_signatures/#{delivery.id}" }
  let(:gateway) { instance_double(JrcBackoffice::Signatures::Gateway) }
  let(:external_id) { SecureRandom.uuid }
  let(:payload) do
    { external_id: external_id, state: 'completion_reported', document_references: ['1'], observed_at: Time.current.iso8601(6),
      signers: delivery.snapshot.fetch('recipients').map do |row|
        { id: row.fetch('position').to_s, name: row.fetch('name'), email: row.fetch('email'), completed: true,
          signed_at: Time.current.iso8601(6), provider_state: 'completed' }
      end,
      signed_document: "%PDF-1.4\nSYNTHETIC API SIGNED FILE", certificate: "%PDF-1.4\nSYNTHETIC API CERTIFICATE" }
  end

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && config.database == 'jrc_rel_v2_candidate_test' && config.host == 'jrc-rel-v2-pg-20261101'
    raise 'Owned synthetic evidence API database required' unless owned

    domain
    role = create(:custom_role, account: account, permissions: %w[jrc_crm jrc_approvals_request_create])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
  end

  it 'serves safe persisted metadata without any provider call or automatic signature mutation' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    get "#{url}/evidence", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'not_received', 'can_capture' => false, 'can_accept' => false)
    expect(response.headers).to include('Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff')
    expect(response.body).not_to include('source_snapshot', 'recipients', 'private_key', 'external_account_id')
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  # Keep one real authenticated lifecycle together so that all assertions inspect the same immutable version.
  # rubocop:disable RSpec/MultipleExpectations
  it 'captures, quarantines, downloads and explicitly accepts the exact version through authenticated HTTP commands' do
    delivery.events.create!(account: account, connection: delivery.connection, kind: 'send_confirmed', event_key: 'synthetic-api-ack',
                            external_id: external_id, source_snapshot: '{}')
    allow(JrcBackoffice::Signatures::Gateway).to receive(:new).with(connection: delivery.connection).and_return(gateway)
    allow(gateway).to receive(:evidence).with(external_id).and_return(payload)
    post "#{url}/capture_evidence", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to include('state' => 'pending', 'can_accept' => false)
    bundle = JrcBackoffice::SignatureArtifactBundle.find_by!(account: account, delivery: delivery)
    get "#{url}/evidence/signed_document/download", headers: headers
    expect(response).to have_http_status(:conflict)
    [bundle.signed_document, bundle.certificate_document].each do |version|
      JrcBackoffice::DocumentScan.create!(account: account, document_version: version, source_blob: version.file.blob,
                                          attempt: 1, state: 'clean', expected_sha256: version.sha256,
                                          observed_sha256: version.sha256, scanner_adapter: 'clamav-instream-v1')
    end
    get "#{url}/evidence/signed_document/download", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(payload.fetch(:signed_document))
    expect(response.headers['Content-Disposition']).to include('attachment')
    post "#{url}/accept_evidence", headers: headers, params: { signature_evidence: { expected_source_digest: bundle.source_digest } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('accepted' => true, 'can_accept' => false)
    expect(response.body).not_to include('source_snapshot', 'recipients', payload[:signers].first[:email])
    expect(domain[:contract].reload.status).to eq('awaiting_signature')
    crm_url = "/api/v1/accounts/#{account.id}/crm/contracts/#{domain[:contract].id}/signed_document"
    get crm_url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(payload.fetch(:signed_document))
    version = bundle.signed_document
    JrcBackoffice::DocumentScan.create!(account: account, document_version: version, source_blob: version.file.blob,
                                        attempt: 2, state: 'infected', expected_sha256: version.sha256, observed_sha256: version.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    get crm_url, headers: headers
    expect(response).to have_http_status(:conflict)
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    get crm_url, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  # rubocop:enable RSpec/MultipleExpectations
  it 'denies foreign accounts, nonowners and revoked native unit coverage on the direct evidence URLs' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    foreign = create(:user, account: create(:account), role: :administrator)
    get "#{url}/evidence", headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    outsider = approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide])
    get "#{url}/evidence", headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    get "#{url}/evidence", headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{url}/capture_evidence", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
