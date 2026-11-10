require 'rails_helper'
require 'timeout'
require Rails.root.join('db/migrate/20261102100100_allow_signature_reconciliation_observations')

# Committed rows, actual locks/HMAC and an independently visible read lease.
# Every DocuSign/AV reply is simulated; this is not external homologation.
RSpec.describe JrcBackoffice::Signatures::Reconciliation, :approval_core, :authority_core, :signature_delivery_core do
  self.use_transactional_tests = false
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:connection) { domain.fetch(:connection) }
  let(:external_id) { SecureRandom.uuid }
  let(:root) { "https://demo.docusign.net/restapi/v2.1/accounts/#{connection.external_account_id}" }
  let(:lookup) { "#{root}/envelopes?transaction_ids=#{delivery.transaction_id}&count=2" }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Owned committed reconciliation database required' unless Rails.env.test? &&
                                                                    config.database == 'jrc_four_domains_schema_admission_test' &&
                                                                    config.host == 'jrc-rel-v2-pg-20261101'

    domain
    stub_request(:post, 'https://account-d.docusign.com/oauth/token')
      .to_return(status: 200, body: { access_token: 'synthetic-token-only', expires_in: 3600 }.to_json)
    stub_request(:get, 'https://account-d.docusign.com/oauth/userinfo')
      .to_return(status: 200, body: { sub: connection.impersonated_user_id,
                                      accounts: [{ account_id: connection.external_account_id, base_uri: 'https://demo.docusign.net' }] }.to_json)
    stub_request(:post, "#{root}/envelopes").to_timeout
    stub_request(:get, lookup).to_return(status: 200, body: { envelopes: [{ envelopeId: external_id }], totalSetSize: '1' }.to_json)
    stub_request(:get, "#{root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, transactionId: delivery.transaction_id, status: 'sent' }.to_json)
  end

  it 'leaves prepared intents alone and refuses an uncommitted caller without creating observations or provider I/O' do
    expect { described_class.new(delivery_id: delivery.id).call }.not_to change(delivery.events, :count)
    ApplicationRecord.transaction do
      expect do
        described_class.new(delivery_id: delivery.id).call
      end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'RECONCILIATION_REQUIRES_COMMITTED_INTENT')
    end
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'recovers a timed-out send on its original connection, commits the read lease first and binds an early authenticated receipt' do
    send_state = JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call.state
    receipt = signature_receipt(connection: connection, event: 'envelope-completed', external_id: external_id, at: 18.minutes.from_now)
    expect([send_state, JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call]).to eq(['uncertain', :unbound])
    replacement = synthetic_delivery_connection(domain[:account])
    travel 17.minutes
    stub_request(:get, lookup).with do
      rows = Timeout.timeout(15) do
        Thread.new do
          ApplicationRecord.connection_pool.with_connection do |sql|
            sql.select_value('SELECT COUNT(*) FROM jrc_backoffice_signature_delivery_events ' \
                             "WHERE delivery_id=#{delivery.id} AND kind='reconciliation_started'").to_i
          end
        end.value
      end
      expect([ApplicationRecord.connection.transaction_open?, rows]).to eq([false, 1])
      true
    end.to_return(status: 200, body: { envelopes: [{ envelopeId: external_id }], totalSetSize: '1' }.to_json)
    result = described_class.new(delivery_id: delivery.id).call
    expect([result.state, delivery.reload.external_id, delivery.connection_id == replacement.id, domain[:contract].reload.signature_status])
      .to eq(['sent', external_id, false, 'sent'])
    expect(JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call).to eq(:processed)
    expect([delivery.reload.state, JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])]).to eq(['completion_reported', false])
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
    expect(WebMock).to have_requested(:get, lookup).once
  end

  it 'keeps an empty lookup reserved, rate limits across retries and records completion without declaring a verified signature' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    travel 17.minutes
    stub_request(:get, lookup).to_return do
      travel 2.minutes # Simulated delay verifies spacing from the finished read.
      { status: 200, body: { envelopes: [], totalSetSize: '0' }.to_json }
    end
    result = described_class.new(delivery_id: delivery.id).call
    expect([result.state, delivery.events.order(:id).last.snapshot, JrcBackoffice::Signatures::DeliveryGuard.active(domain[:contract]).pluck(:id)])
      .to eq(['uncertain', { 'code' => 'SEND_NOT_RESOLVED' }, [delivery.id]])
    expect do
      described_class.new(delivery_id: delivery.id).call
      travel 15.minutes
      described_class.new(delivery_id: delivery.id).call
    end.not_to change(delivery.events, :count)
    travel 2.minutes
    stub_request(:get, lookup).to_return(status: 200, body: { envelopes: [{ envelopeId: external_id }] }.to_json)
    stub_request(:get, "#{root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, transactionId: delivery.transaction_id, status: 'completed' }.to_json)
    result = described_class.new(delivery_id: delivery.id).call
    expect([result.state, domain[:contract].reload.signature_status, JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])])
      .to eq(['completion_reported', 'sent', false])
    older = signature_receipt(connection: connection, event: 'envelope-voided', external_id: external_id, at: 1.minute.ago)
    expect([JrcBackoffice::Signatures::Notifications.new(receipt_id: older.id).call, delivery.reload.state]).to eq([:ignored, 'completion_reported'])
    expect { AllowSignatureReconciliationObservations.new.migrate(:down) }
      .to raise_error(ActiveRecord::IrreversibleMigration, /Preserve signature reconciliation history/)
    expect(WebMock).to have_requested(:get, lookup).twice
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'retains the reservation after a read timeout and stops transaction lookups when the original seven-day window expires' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    travel 17.minutes
    stub_request(:get, lookup).to_timeout
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('uncertain')
    expect(delivery.events.order(:id).last.snapshot).to eq('code' => 'PROVIDER_UNAVAILABLE')
    travel 7.days
    expect { described_class.new(delivery_id: delivery.id).call }.not_to change(delivery.events, :count)
    expect(described_class.candidates.pluck(:id)).not_to include(delivery.id)
    expect(JrcBackoffice::Signatures::DeliveryGuard.active(domain[:contract])).to include(delivery)
    expect(WebMock).to have_requested(:get, lookup).once
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'rejects a plausible envelope with a different transaction and keeps all identifiers private in outcome facts' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    travel 17.minutes
    stub_request(:get, "#{root}/envelopes/#{external_id}")
      .to_return(status: 200, body: { envelopeId: external_id, transactionId: SecureRandom.uuid, status: 'sent' }.to_json)
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('uncertain')
    event = delivery.events.order(:id).last
    expect(event.snapshot).to eq('code' => 'PROVIDER_RESPONSE_INVALID')
    expect(event.as_json.to_s).not_to include(delivery.transaction_id, external_id, 'synthetic-token-only')
    expect(delivery.reload.external_id).to be_nil
  end

  it 'rechecks revoked unit coverage before querying without treating the uncertain send as safely canceled' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    domain[:account].jrc_crm_user_business_units.where(user: domain[:actor]).each { |row| row.update!(active: false) }
    travel 17.minutes
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('uncertain')
    expect(delivery.events.order(:id).last.snapshot).to eq('code' => 'DELIVERY_ACCESS_DENIED')
    expect(WebMock).not_to have_requested(:get, lookup)
    expect(JrcBackoffice::Signatures::DeliveryGuard.active(domain[:contract])).to include(delivery)
  end

  it 'reserves a crashed dispatcher and a crashed reconciliation lease instead of claiming either operation happened' do
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'dispatch_started', event_key: 'synthetic-crashed-dispatch',
                            source_snapshot: '{}')
    travel 17.minutes
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'reconciliation_started',
                            event_key: 'synthetic-crashed-query', source_snapshot: '{}')
    expect(delivery.reload.state).to eq('dispatching')
    expect { described_class.new(delivery_id: delivery.id).call }.not_to change(delivery.events, :count)
    travel 17.minutes
    stub_request(:get, lookup).to_return(status: 200, body: { envelopes: [], totalSetSize: '0' }.to_json)
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('dispatching')
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
    expect(WebMock).to have_requested(:get, lookup).once
  end

  it 'permits read-only recovery for a closed request without granting a new contract write or send' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    domain[:operation].update!(status: 'canceled')
    travel 17.minutes
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('sent')
    expect(domain[:operation].reload.status).to eq('canceled')
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  end

  it 'denies a suspended account before provider I/O while keeping the historical uncertain reservation' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    domain[:account].update!(status: :suspended)
    travel 17.minutes
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('uncertain')
    expect(delivery.events.order(:id).last.snapshot).to eq('code' => 'DELIVERY_ACCESS_DENIED')
    expect(WebMock).not_to have_requested(:get, lookup)
  end

  it 'allows only one concurrent read window even while the first provider lookup is still pending' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    travel 17.minutes
    entered = Queue.new
    release = Queue.new
    stub_request(:get, lookup).to_return do
      entered << true
      Timeout.timeout(30) { release.pop }
      { status: 200, body: { envelopes: [{ envelopeId: external_id }] }.to_json }
    end
    worker = Thread.new do
      ApplicationRecord.connection_pool.with_connection { described_class.new(delivery_id: delivery.id).call }
    end
    Timeout.timeout(60) { entered.pop }
    expect(Timeout.timeout(15) { described_class.new(delivery_id: delivery.id).call.state }).to eq('uncertain')
    release << true
    expect(Timeout.timeout(30) { worker.value }.state).to eq('sent')
    expect(delivery.events.where(kind: 'reconciliation_started').count).to eq(1)
    expect(WebMock).to have_requested(:get, lookup).once
    expect(WebMock).to have_requested(:post, "#{root}/envelopes").once
  ensure
    release << true if release
    worker&.join(30)
  end

  it 'selects bounded eligible jobs and removes recovered sends from subsequent recovery batches' do
    JrcBackoffice::Signatures::Dispatch.new(delivery_id: delivery.id).call
    expect(described_class.candidates.pluck(:id)).not_to include(delivery.id)
    travel 17.minutes
    ids = described_class.candidates.pluck(:id)
    expect(ids).to include(delivery.id)
    expect(ids.length).to be <= 100
    expect { JrcBackoffice::SignatureReconciliationRecoveryJob.perform_now }
      .to have_enqueued_job(JrcBackoffice::SignatureReconciliationJob).with(delivery.id)
    JrcBackoffice::SignatureReconciliationJob.perform_now(delivery.id)
    expect(described_class.candidates.pluck(:id)).not_to include(delivery.id)
    expect(delivery.reload.state).to eq('sent')
  end

  it 'repairs a recovered acknowledgement on retry without another lookup or POST when native projection first conflicts' do
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'dispatch_started', event_key: 'synthetic-lost-ack',
                            source_snapshot: '{}')
    conflict = SecureRandom.uuid
    domain[:contract].update!(signature_external_id: conflict)
    travel 17.minutes
    expect do
      described_class.new(delivery_id: delivery.id).call
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT')
    expect([delivery.reload.state, delivery.external_id, domain[:contract].reload.signature_external_id]).to eq(['sent', external_id, conflict])
    expect do
      described_class.new(delivery_id: delivery.id).call
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_PROJECTION_CONFLICT')
    # Test-only correction of an untracked/conflicting pointer.
    domain[:contract].update!(signature_external_id: external_id)
    expect(described_class.new(delivery_id: delivery.id).call.state).to eq('sent')
    expect(domain[:contract].reload.signature_status).to eq('sent')
    expect(WebMock).to have_requested(:get, lookup).once
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end

  it 'rechecks the original sender coverage before repairing an already bound acknowledgement without another provider call' do
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-bound-ack',
                            external_id: external_id, source_snapshot: '{}')
    original_facts = delivery.events.order(:id).pluck(:id)
    domain[:account].jrc_crm_user_business_units.where(user: domain[:actor]).each { |grant| grant.update!(active: false) }
    expect do
      described_class.new(delivery_id: delivery.id).call
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(delivery.events.order(:id).pluck(:id)).to eq(original_facts)
    expect([delivery.reload.state, domain[:contract].reload.signature_status]).to eq(%w[sent not_started])
    expect(WebMock).not_to have_requested(:get, lookup)
    expect(WebMock).not_to have_requested(:post, "#{root}/envelopes")
  end
end
