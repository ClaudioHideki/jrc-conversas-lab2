require 'rails_helper'

RSpec.describe JrcBackoffice::SignatureNotificationJob, :approval_core, :authority_core, :signature_delivery_core, type: :job do
  self.use_transactional_tests = false
  include ActiveJob::TestHelper
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:connection) { domain.fetch(:connection) }
  let(:external_id) { SecureRandom.uuid }
  let(:receipt) { signature_receipt(connection: connection, event: 'envelope-completed', external_id: external_id) }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Owned notification job database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_admission_test' &&
                                                            config.host == 'jrc-rel-v2-pg-20261101'

    domain
    clear_enqueued_jobs
  end

  it 'queues after receipt commit and recovers a receipt that arrived before its durable envelope binding' do
    queued_before_commit = nil
    JrcBackoffice::SignatureNotification.transaction do
      receipt
      queued_before_commit = enqueued_jobs.select { |row| row[:job] == described_class }.map { |row| row[:args] }
    end
    queued_after_commit = enqueued_jobs.select { |row| row[:job] == described_class }.map { |row| row[:args] }
    expect([queued_before_commit, queued_after_commit]).to eq([[], [[receipt.id]]])
    perform_enqueued_jobs(only: described_class)
    expect(receipt.reload.state).to eq('received')
    # Simulated provider acknowledgement, not a real external send.
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    expect { JrcBackoffice::SignatureNotificationRecoveryJob.perform_now }.to have_enqueued_job(described_class).with(receipt.id)
    perform_enqueued_jobs(only: described_class)
    expect([receipt.reload.state, delivery.reload.state]).to eq(%w[processed completion_reported])
    expect([domain[:contract].reload.signature_status, JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])]).to eq(['sent', false])
    expect { JrcBackoffice::SignatureNotificationRecoveryJob.perform_now }.not_to have_enqueued_job(described_class)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'records a safe failed receipt for a suspended account without applying an external fact or releasing the operation' do
    receipt
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    domain[:account].update!(status: :suspended)
    expect { described_class.perform_now(receipt.id) }.not_to change(delivery.events, :count)
    expect([receipt.reload.state, delivery.reload.state]).to eq(%w[failed sent])
    expect(domain[:contract].reload.signature_status).to eq('not_started')
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'reprojects a processed receipt after a worker stops between committed facts and the native contract update' do
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    expect(JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call).to eq(:processed)
    expect([receipt.reload.state, delivery.state, domain[:contract].reload.signature_status])
      .to eq(%w[processed completion_reported not_started])
    expect { described_class.perform_now(receipt.id) }.not_to change(delivery.events, :count)
    expect([receipt.reload.state, domain[:contract].reload.signature_status, JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])])
      .to eq(['processed', 'sent', false])
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'rechecks account revocation on a processed retry and does not project the previously accepted fact' do
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call
    domain[:account].disable_features!('jrc_crm')
    expect { described_class.perform_now(receipt.id) }.not_to change(delivery.events, :count)
    expect([receipt.reload.state, delivery.reload.state, domain[:contract].reload.signature_status])
      .to eq(%w[failed completion_reported not_started])
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end

  it 'retains authenticated facts on projection conflict and retries the same receipt without duplicating cancellation' do
    delivery.events.create!(account: delivery.account, connection: connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    newer_reference = SecureRandom.uuid
    domain[:contract].update!(signature_external_id: newer_reference, signature_status: 'sent')
    canceled = signature_receipt(connection: connection, event: 'envelope-voided', external_id: external_id)
    original_hash = canceled.body_sha256
    described_class.perform_now(canceled.id)
    expect([canceled.reload.state, delivery.reload.state, domain[:contract].reload.signature_external_id])
      .to eq(['failed', 'canceled', newer_reference])
    expect([canceled.body_sha256, canceled.payload.dig('data', 'envelopeId')]).to eq([original_hash, external_id])
    # Explicit synthetic repair of the conflicting native pointer; no public
    # bypass or external cancellation is introduced by this test setup.
    domain[:contract].update!(signature_external_id: external_id)
    expect { described_class.perform_now(canceled.id) }.not_to change(delivery.events, :count)
    expect([canceled.reload.state, domain[:contract].reload.signature_status]).to eq(%w[processed canceled])
    expect(delivery.events.where(kind: 'envelope_canceled').count).to eq(1)
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  end
end
