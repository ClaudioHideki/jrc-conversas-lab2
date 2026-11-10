require 'rails_helper'
require 'timeout'

# Real committed rows and PostgreSQL lock ordering; no provider/AV homologation.
RSpec.describe JrcBackoffice::Signatures::DeliveryProjection, :approval_core, :authority_core, :signature_delivery_core do
  self.use_transactional_tests = false
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:contract) { domain.fetch(:contract) }
  let(:external_id) { SecureRandom.uuid }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Owned committed projection database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_admission_test' &&
                                                                config.host == 'jrc-rel-v2-pg-20261101'

    delivery.events.create!(account: delivery.account, connection: delivery.connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    described_class.call(delivery)
  end

  it 'reads the latest committed fact after waiting and cannot restore sent over a projected authenticated cancellation' do
    parent_pid = ApplicationRecord.connection.select_value('SELECT pg_backend_pid()')
    worker_pid = Queue.new
    worker = nil
    contract.with_lock('FOR NO KEY UPDATE') do
      worker = Thread.new do
        ApplicationRecord.connection_pool.with_connection do |sql|
          worker_pid << sql.select_value('SELECT pg_backend_pid()')
          described_class.call(JrcBackoffice::SignatureDelivery.find(delivery.id))
        end
      end
      pid = Timeout.timeout(15) { worker_pid.pop }
      blocked = Timeout.timeout(20) do
        loop do
          break true if ApplicationRecord.connection.select_value("SELECT #{Integer(parent_pid)} = ANY(pg_blocking_pids(#{Integer(pid)}))")

          sleep 0.02
        end
      end
      expect([pid == parent_pid, blocked]).to eq([false, true])
      receipt = signature_receipt(connection: delivery.connection, event: 'envelope-voided', external_id: external_id)
      expect(JrcBackoffice::Signatures::Notifications.new(receipt_id: receipt.id).call).to eq(:processed)
      described_class.call(delivery)
      expect(contract.reload.signature_status).to eq('canceled')
    end
    expect(Timeout.timeout(30) { worker.value }.state).to eq('canceled')
    expect([delivery.reload.state, contract.reload.signature_status, contract.signature_external_id]).to eq(['canceled', 'canceled', external_id])
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(WebMock).not_to have_requested(:any, /docusign/)
  ensure
    worker&.join(30)
  end
end
