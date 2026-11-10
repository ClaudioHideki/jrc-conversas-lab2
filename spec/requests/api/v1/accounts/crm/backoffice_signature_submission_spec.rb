require 'rails_helper'

RSpec.describe 'Backoffice signature submission API', :approval_core, :authority_core, :signature_delivery_core, type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:legal) { signature_legal_context(domain) }
  let(:connection) { synthetic_delivery_connection(account) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{domain[:operation].id}/contract_signatures" }
  let(:input) do
    { version_id: legal[:version].id, authority_proposal_id: legal[:proposal].id, expected_connection_id: connection.id,
      expected_source_digest: legal[:version].source_digest, idempotency_key: SecureRandom.uuid }
  end

  before do
    raise 'Owned submission API database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_four_domains_schema_admission_test'

    legal
    connection
    role = create(:custom_role, account: account, permissions: %w[jrc_crm jrc_approvals_request_create])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    clear_enqueued_jobs
  end

  it 'previews the exact authorized version and ready connection without sending, exposing secrets or creating an intent' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    expect { get "#{url}/preparation", headers: headers }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'can_send' => true, 'version' => include('id' => legal[:version].id, 'pdf_sha256' => legal[:version].pdf_sha256),
      'authority_proposal_id' => legal[:proposal].id, 'connection' => include('id' => connection.id, 'environment' => 'demo')
    )
    expect(response.body).not_to include('source_snapshot', 'recipients', 'private_key', 'connect_hmac_keys', 'personal_tax_identifier',
                                         connection.external_account_id, '11144477735', '52998224725')
    expect(response.headers).to include('Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff')
  end

  it 'registers one durable intent and reuses it on retry without claiming sent or verified' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    expect { post url, headers: headers, params: { signature_delivery: input } }
      .to have_enqueued_job(JrcBackoffice::SignatureDispatchJob)
    expect(response).to have_http_status(:accepted)
    id = response.parsed_body.fetch('id')
    expect(response.parsed_body).to include('state' => 'prepared', 'external_id' => nil)
    expect { post url, headers: headers, params: { signature_delivery: input } }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:accepted)
    record = JrcBackoffice::SignatureDelivery.find(id)
    expect({ replay_id: response.parsed_body.fetch('id'), events: record.events.pluck(:kind),
             native_state: domain[:contract].reload.signature_status, released: JrcBackoffice::SignatureRelease.satisfied?(domain[:operation]),
             verifier: JrcApprovals::SignatureEvidence.verifier })
      .to eq(replay_id: id, events: ['prepared'], native_state: 'not_started', released: false, verifier: nil)
  end

  it 'rechecks an identity changed after preview and leaves no partial intent' do
    get "#{url}/preparation", headers: headers
    expect(response.parsed_body.fetch('can_send')).to be(true)
    domain[:customer_person].update!(name: 'TESTE SINTÉTICO — Identidade alterada depois da prévia')
    expect { post url, headers: headers, params: { signature_delivery: input } }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('AUTHORITY_APPROVAL_REQUIRED')
  end

  it 'refuses a replaced default and never redirects the intent to the new connection' do
    input
    manager = JrcBackoffice::SignatureConfiguration.new(account: account, actor: connection.created_by)
    replacement = manager.save!(attributes: {}, expected_revision: connection.revision).connection
    # Synthetic readiness only; no external authorization is claimed.
    replacement.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    get "#{url}/preparation", headers: headers
    expect(response.parsed_body.dig('connection', 'id')).to eq(replacement.id)
    expect { post url, headers: headers, params: { signature_delivery: input } }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('CONNECTION_CHANGED')
  end

  it 'explains missing readiness and rejects forged connection IDs without exposing provider details' do
    connection.update!(authorization_checked_at: nil)
    get "#{url}/preparation", headers: headers
    expect(response.parsed_body).to eq('can_send' => false, 'blocked_code' => 'CONNECTION_NOT_READY')
    expect { post url, headers: headers, params: { signature_delivery: input } }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to eq('code' => 'CONNECTION_NOT_READY')
  end

  it 'ignores account, actor and unit fields supplied by the client as sources of authority' do
    foreign = create(:account)
    hostile = input.merge(account_id: foreign.id, created_by_id: 0, business_unit_id: 0, connection_id: 0)
    post url, headers: headers, params: { signature_delivery: hostile }
    expect(response).to have_http_status(:accepted)
    record = JrcBackoffice::SignatureDelivery.find(response.parsed_body.fetch('id'))
    expect([record.account_id, record.created_by_id, record.connection_id]).to eq([account.id, actor.id, connection.id])
    expect(record.snapshot.fetch('account_id')).to eq(account.id)
  end

  it 'denies foreign accounts, nonowners and revoked unit coverage for preview and submission' do
    outsider = approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide]).user
    get "#{url}/preparation", headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:user, account: create(:account), role: :administrator)
    post url, headers: foreign.create_new_auth_token, params: { signature_delivery: input }
    expect(response).to have_http_status(:unauthorized)
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    get "#{url}/preparation", headers: headers
    expect(response).to have_http_status(:not_found)
    expect { post url, headers: headers, params: { signature_delivery: input } }.not_to change(JrcBackoffice::SignatureDelivery, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'cancels only a prepared intent idempotently and never enqueues an external cancellation' do
    post url, headers: headers, params: { signature_delivery: input }
    record = JrcBackoffice::SignatureDelivery.find(response.parsed_body.fetch('id'))
    clear_enqueued_jobs
    2.times { post "#{url}/#{record.id}/cancel_prepared", headers: headers }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('state')).to eq('canceled')
    expect(record.events.where(kind: 'canceled_before_send').count).to eq(1)
    expect(account.jrc_crm_audit_events.where(event_type: 'signature_delivery_canceled').count).to eq(1)
    expect(enqueued_jobs).to be_empty
    expect(domain[:contract].reload.signature_status).to eq('not_started')
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
  end

  it 'refuses local cancellation once a dispatch has been claimed, preserving the uncertain reservation' do
    post url, headers: headers, params: { signature_delivery: input }
    record = JrcBackoffice::SignatureDelivery.find(response.parsed_body.fetch('id'))
    record.events.create!(account: account, connection: connection, kind: 'dispatch_started', event_key: 'synthetic-claim', source_snapshot: '{}')
    post "#{url}/#{record.id}/cancel_prepared", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('DELIVERY_ALREADY_DISPATCHED')
    expect(record.reload.state).to eq('dispatching')
    expect(record.events.where(kind: 'canceled_before_send')).to be_empty
    expect(JrcBackoffice::Signatures::DeliveryGuard.active(domain[:contract]).pluck(:id)).to eq([record.id])
  end

  it 'denies direct cancellation after scope revocation and preserves the original intent and connection' do
    post url, headers: headers, params: { signature_delivery: input }
    record = JrcBackoffice::SignatureDelivery.find(response.parsed_body.fetch('id'))
    source = record.snapshot
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    post "#{url}/#{record.id}/cancel_prepared", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(record.reload.state).to eq('prepared')
    expect(record.snapshot).to eq(source)
    expect(record.events.where(kind: 'canceled_before_send')).to be_empty
  end

  it 'requires a new immutable version after a locally canceled intent instead of previewing an impossible second send' do
    post url, headers: headers, params: { signature_delivery: input }
    id = response.parsed_body.fetch('id')
    post "#{url}/#{id}/cancel_prepared", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{url}/preparation", headers: headers
    expect(response.parsed_body).to eq('can_send' => false, 'blocked_code' => 'DELIVERY_VERSION_ALREADY_REGISTERED')
    post url, headers: headers, params: { signature_delivery: input.merge(idempotency_key: SecureRandom.uuid) }
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('DELIVERY_VERSION_ALREADY_REGISTERED')
  end
end
