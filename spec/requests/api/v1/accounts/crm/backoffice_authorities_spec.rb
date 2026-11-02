require 'rails_helper'

RSpec.describe 'Backoffice representation and native Central API', :approval_core, :authority_core, type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:reviewer) { approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide]) }
  let(:document) { authority_document(domain) }
  let(:roster) { authority_roster(domain) }
  let(:version) do
    document
    roster
    domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(domain[:contract].id),
                              change_reason: 'TESTE SINTÉTICO — Versão da API jurídica.')
  end
  let(:input) { authority_input(version, roster, document) }
  let(:policy) { authority_policy(domain, [reviewer]) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}/contract_authorities" }
  let(:proposal) do
    policy
    JrcBackoffice::AuthorityProposals.new(account: account, actor: actor, request_id: domain[:operation].id).create!(**input)
  end

  before do
    raise 'Owned candidate database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    domain
  end

  it 'does not imply that the legacy contract or CPF alone allows proposing powers' do
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('can_propose' => false, 'version' => nil, 'current' => nil)
    expect(response.headers).to include('Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff')
  end

  it 'rolls back the sealed proposal if the native legal policy is missing' do
    post url, headers: headers, params: { authority_proposal: input }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('POLICY_REQUIRED')
    expect(JrcBackoffice::AuthorityProposal.where(account_id: account.id)).to be_empty
    expect(JrcApprovals::Request.where(account_id: account.id)).to be_empty
  end

  it 'creates and reloads a pending case with server-derived account, scope and exact version' do
    policy
    spoofed = input.merge(account_id: 999, user_id: 999, unit_id: 999, powers_verified: true, state: 'approved')
    post url, headers: headers, params: { authority_proposal: spoofed }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('proposal', 'id')
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('current', 'proposal', 'id')).to eq(id)
    expect(response.parsed_body.dig('current', 'status', 'status')).to eq('blocked')
    expect(response.body).not_to include('11144477735', '52998224725', 'source_snapshot', 'content_override', 'identity_id', 'anchor')
    expect(JrcBackoffice::AuthorityProposal.find(id)).to have_attributes(account_id: account.id, contract_version_id: version.id,
                                                                         created_by_id: actor.id)
  end

  it 'gives a designated reviewer the bounded origin and exact private files without granting ordinary Backoffice access' do
    record = proposal
    token = reviewer.user.create_new_auth_token
    get "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}", headers: token
    expect(response).to have_http_status(:not_found)
    get "#{url}/#{record.id}", headers: token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('context', 'customer', 'id')).to eq(domain[:customer].id)
    expect(response.body).not_to include('11144477735', '52998224725', 'source_snapshot', 'content_override')
    get "#{url}/#{record.id}/pdf", headers: token
    expect(response).to have_http_status(:ok)
    expect(Digest::SHA256.hexdigest(response.body)).to eq(version.pdf_sha256)
    get "#{url}/#{record.id}/documents/#{document.id}", headers: token
    expect(Digest::SHA256.hexdigest(response.body)).to eq(document.sha256)
  end

  it 'audits evidence access and denies every file outside the sealed proposal' do
    record = proposal
    token = reviewer.user.create_new_auth_token
    get "#{url}/#{record.id}/pdf", headers: token
    expect(response.headers).to include('Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff')
    audit = account.jrc_crm_audit_events.find_by!(event_type: 'backoffice_authority_evidence_accessed')
    expect(audit.to_value).to include('authority_proposal_id' => record.id, 'contract_version_id' => version.id, 'sha256' => version.pdf_sha256)
    expect(audit.to_json).not_to include('11144477735', '52998224725')
    extra = domain[:documents].upload!(key: 'representation', file: domain[:file], idempotency_key: SecureRandom.uuid)
    get "#{url}/#{record.id}/documents/#{extra.id}", headers: token
    expect(response).to have_http_status(:not_found)
  end

  it 'denies unassigned reviewers, foreign accounts and scope withdrawal including direct PDF URLs' do
    record = proposal
    outsider = approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide])
    get "#{url}/#{record.id}/pdf", headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/#{record.id}", headers: create(:user, account: create(:account), role: :administrator).create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    account.jrc_crm_user_business_units.where(user_id: reviewer.user_id).each { |row| row.update!(active: false) }
    get "#{url}/#{record.id}/pdf", headers: reviewer.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'rejects evidence corruption and rechecks reviewer scope after storage I/O' do
    record = proposal
    token = reviewer.user.create_new_auth_token
    storage = version.pdf_blob.service
    allow(storage).to receive(:download).and_wrap_original do |method, *args|
      result = method.call(*args)
      account.jrc_crm_user_business_units.where(user_id: reviewer.user_id).each { |row| row.update!(active: false) }
      result
    end
    get "#{url}/#{record.id}/pdf", headers: token
    expect(response).to have_http_status(:unauthorized)
    expect(account.jrc_crm_audit_events.where(event_type: 'backoffice_authority_evidence_accessed')).to be_empty
  end

  it 'rejects stale creation with conflict and does not interpret encrypted context failure as a success' do
    proposal
    post url, headers: headers, params: { authority_proposal: input.merge(idempotency_key: SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('AUTHORITY_CONTEXT_CHANGED')
    expect(JrcBackoffice::AuthorityProposal.where(account_id: account.id).count).to eq(1)
  end

  it 'opens the origin from the native approval and records a decision through the single Central endpoint' do
    record = proposal
    native = JrcApprovals::Request.find_by!(account_id: account.id, resource_type: record.class.name, resource_id: record.id)
    token = reviewer.user.create_new_auth_token
    base = "/api/v1/accounts/#{account.id}/approvals/requests/#{native.id}"
    get base, headers: token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('origin')).to include('kind' => 'contract_authority', 'backoffice_request_id' => domain[:operation].id)
    expect(response.parsed_body.fetch('allowed_decisions')).not_to be_empty
    decision = { step_code: 'review', decision: 'approved', reason: 'TESTE SINTÉTICO — Evidência e representação conferidas.',
                 expected_version: native.lock_version, idempotency_key: SecureRandom.uuid }
    post "#{base}/decide", headers: token, params: { decision: decision }, as: :json
    expect(response).to have_http_status(:ok)
    get "#{url}/#{record.id}", headers: headers
    expect(response.parsed_body.dig('status', 'status')).to eq('verified')
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'keeps the legal history but cannot declare powers verified after the Central is disabled' do
    record = proposal
    account.disable_features!('jrc_approvals')
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('can_propose' => false, 'approvals_enabled' => false)
    expect(response.parsed_body.dig('current', 'status')).to include('status' => 'unavailable')
    post url, headers: headers, params: { authority_proposal: input.merge(expected_revision: 1, idempotency_key: SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.revision).to eq(1)
  end

  it 'does not count or disclose a sealed legal case outside the current users original unit coverage' do
    record = proposal
    other = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Destino', code: 'DESTINATION', company_id: domain[:company].id)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: domain[:company], business_unit: other,
                                                structure_managed: true, active: true)
    # Hostile/legacy relocation fixture: a visible current origin must not grant
    # access to representation evidence sealed under a different unit.
    [domain[:operation], domain[:order], domain[:contract]].each do |origin|
      ApplicationRecord.connection.execute("UPDATE #{origin.class.quoted_table_name} SET business_unit_id=#{other.id} WHERE id=#{origin.id}")
    end
    account.jrc_crm_user_business_units.where(user: actor, business_unit_id: domain[:unit].id).each { |row| row.update!(active: false) }
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to be_empty
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    expect(response.parsed_body.fetch('current')).to be_nil
    get "#{url}/#{record.id}/pdf", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
