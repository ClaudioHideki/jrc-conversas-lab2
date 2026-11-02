require 'rails_helper'
require 'timeout'

# Runs with committed rows and independent PostgreSQL connections. All
# DocuSign HTTP and scanner replies are simulated, never demo homologation.
RSpec.describe JrcBackoffice::Signatures::Dispatch, :approval_core, :authority_core, :signature_delivery_core do
  self.use_transactional_tests = false
  let(:domain) { Time.use_zone('America/Sao_Paulo') { admitted_signature_domain } }
  let(:delivery) { domain.fetch(:delivery) }
  let(:connection) { domain.fetch(:connection) }
  let(:external_id) { SecureRandom.uuid }
  let(:root) { "https://demo.docusign.net/restapi/v2.1/accounts/#{connection.external_account_id}" }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Dedicated owned dispatch database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_admission_test' &&
                                                              config.host == 'jrc-rel-v2-pg-20261101'

    domain
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo')
      .to_return(status: 200, body: { sub: connection.impersonated_user_id,
                                      accounts: [{ account_id: connection.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json)
  end

  it 'commits both intent and claim before POST, binds the exact version and keeps unsigned operations blocked' do
    member = domain[:account].account_users.find_by!(user: domain[:actor])
    role = create(:custom_role, account: domain[:account], permissions: %w[jrc_crm jrc_approvals_request_create])
    member.update!(role: :agent, custom_role: role)
    main_pid = ApplicationRecord.connection.select_value('SELECT pg_backend_pid()')
    stub_request(:post, "#{root}/envelopes").with do |request|
      expect(ApplicationRecord.connection.transaction_open?).to be(false)
      proof = Timeout.timeout(15) do
        Thread.new do
          ApplicationRecord.connection_pool.with_connection do |sql|
            [sql.select_value('SELECT pg_backend_pid()'),
             sql.select_value("SELECT COUNT(*) FROM jrc_backoffice_signature_deliveries WHERE id=#{delivery.id}").to_i,
             sql.select_value('SELECT COUNT(*) FROM jrc_backoffice_signature_delivery_events ' \
                              "WHERE delivery_id=#{delivery.id} AND kind='dispatch_started'").to_i]
          end
        end.value
      end
      expect(proof).to match([be_a(Integer), 1, 1])
      expect(proof.first).not_to eq(main_pid)
      payload = JSON.parse(request.body)
      expect(payload['transactionId']).to eq(delivery.transaction_id)
      expect(Digest::SHA256.hexdigest(Base64.decode64(payload.fetch('documents').first.fetch('documentBase64'))))
        .to eq(domain[:version].pdf_sha256)
      payload.dig('recipients', 'signers').map { |row| row['recipientId'] } == %w[1 2]
    end.to_return(status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json)
    result = Time.use_zone('UTC') { described_class.new(delivery_id: delivery.id).call }
    expect({ state: result.state, external_id: result.external_id, contract_state: domain[:contract].reload.signature_status,
             released: JrcBackoffice::SignatureRelease.satisfied?(domain[:operation]) })
      .to eq(state: 'sent', external_id: external_id, contract_state: 'sent', released: false)
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'rejects an uncommitted caller before a claim or external request can happen' do
    JrcBackoffice::SignatureDelivery.transaction do
      expect do
        described_class.new(delivery_id: delivery.id).call
      end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DISPATCH_REQUIRES_COMMITTED_INTENT')
    end
    expect(delivery.reload.state).to eq('prepared')
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end

  it 'reserves a timed-out send and never repeats POST on worker retries' do
    stub_request(:post, "#{root}/envelopes").to_timeout
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('uncertain')
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('uncertain')
    expect(delivery.reload.external_id).to be_nil
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'blocks a queued admission after sender coverage is revoked without sending or changing the pinned history' do
    source = delivery.snapshot
    domain[:account].jrc_crm_user_business_units.where(user: domain[:actor]).each { |row| row.update!(active: false) }
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('blocked')
    expect(delivery.reload.snapshot).to eq(source)
    expect(domain[:contract].reload.signature_status).to eq('not_started')
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end

  it 'stores an acknowledged send even when sender authority disappears during provider I/O' do
    stub_request(:post, "#{root}/envelopes").to_return do
      domain[:account].jrc_crm_user_business_units.where(user: domain[:actor]).each { |row| row.update!(active: false) }
      { status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json }
    end
    result = described_class.new(delivery_id: delivery.id).call
    expect(result.state).to eq('sent')
    expect(result.external_id).to eq(external_id)
    expect(result.events.where(kind: 'send_confirmed').count).to eq(1)
    expect(domain[:contract].reload.signature_status).to eq('sent')
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'preserves the provider receipt when native projection conflicts and never resends to repair a view' do
    previous_reference = SecureRandom.uuid
    domain[:contract].update!(signature_external_id: previous_reference)
    stub_request(:post, "#{root}/envelopes").to_return(status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json)
    expect do
      described_class.new(delivery_id: delivery.id).call
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT')
    expect(delivery.reload.external_id).to eq(external_id)
    expect(delivery.state).to eq('sent')
    expect(domain[:contract].reload.signature_external_id).to eq(previous_reference)
    expect do
      described_class.new(delivery_id: delivery.id).call
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT')
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'allows only one concurrent worker to POST and preserves the admitted connection after a new default is configured' do
    replacement = synthetic_delivery_connection(domain[:account])
    entered = Queue.new
    release = Queue.new
    stub_request(:post, "#{root}/envelopes").to_return do
      entered << true
      Timeout.timeout(30) { release.pop }
      { status: 201, body: { envelopeId: external_id, status: 'sent' }.to_json }
    end
    worker = Thread.new do
      ApplicationRecord.connection_pool.with_connection { described_class.new(delivery_id: delivery.id).call }
    end
    Timeout.timeout(60) { entered.pop }
    expect(Timeout.timeout(15) { described_class.new(delivery_id: delivery.id).call.state }).to eq('dispatching')
    release << true
    expect(Timeout.timeout(30) { worker.value }.state).to eq('sent')
    expect(delivery.connection_id).not_to eq(replacement.id)
    expect(delivery.reload.external_id).to eq(external_id)
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  ensure
    release << true if release
    worker&.join(30)
  end

  it 'blocks corrupted source bytes after admission without claiming or posting an envelope' do
    blob = domain[:version].pdf_blob
    original = blob.download
    blob.service.upload(blob.key, StringIO.new('%PDF-synthetic-corruption-after-admission'), checksum: nil)
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('blocked')
    expect(delivery.events.where(kind: 'dispatch_started')).to be_empty
    expect(delivery.events.last.snapshot).to eq('code' => 'AUTHORITY_EVIDENCE_UNAVAILABLE')
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  ensure
    blob.service.upload(blob.key, StringIO.new(original), checksum: nil) if original
  end
end
