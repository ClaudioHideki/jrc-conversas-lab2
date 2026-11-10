require 'rails_helper'
require 'timeout'

# Committed synthetic native records, fake provider bytes and test job adapter.
# No DocuSign requests, real signatures or antivirus acceptance are implied.
RSpec.describe JrcBackoffice::Signatures::Artifacts, :approval_core, :authority_core, :signature_delivery_core do
  self.use_transactional_tests = false
  let(:domain) { admitted_signature_domain }
  let(:delivery) { domain.fetch(:delivery) }
  let(:external_id) { SecureRandom.uuid }
  let(:gateway) { instance_double(JrcBackoffice::Signatures::Gateway) }
  let(:payload) do
    { external_id: external_id, state: 'completion_reported', document_references: ['1'], observed_at: Time.current.iso8601(6),
      signers: delivery.snapshot.fetch('recipients').map do |row|
        { id: row.fetch('position').to_s, name: row.fetch('name'), email: row.fetch('email'), completed: true,
          signed_at: Time.current.iso8601(6), provider_state: 'completed' }
      end,
      signed_document: "%PDF-1.4\nSYNTHETIC SIGNED FILE ONLY", certificate: "%PDF-1.4\nSYNTHETIC CERTIFICATE ONLY" }
  end
  let(:service) { described_class.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id) }

  before do
    config = ActiveRecord::Base.connection_db_config
    unless Rails.env.test? && config.database == 'jrc_rel_v2_candidate_test' && config.host == 'jrc-rel-v2-pg-20261101'
      raise 'Use only the owned isolated evidence candidate database'
    end

    delivery.events.create!(account: delivery.account, connection: delivery.connection, kind: 'send_confirmed', event_key: 'synthetic-ack',
                            external_id: external_id, source_snapshot: '{}')
    allow(JrcBackoffice::Signatures::Gateway).to receive(:new).with(connection: delivery.connection).and_return(gateway)
    allow(gateway).to receive(:evidence).with(external_id).and_return(payload)
  end

  it 'persists exact-version private immutable files and audit while keeping unscanned artifacts and contract release blocked' do
    bundle = service.capture!(delivery_id: delivery.id)
    expect(bundle.integrity?).to be(true)
    expect([bundle.signed_document.file.download, bundle.certificate_document.file.download]).to eq(payload.values_at(:signed_document, :certificate))
    expect { JrcBackoffice::DocumentSafety.new(bundle.signed_document).bytes! }.to raise_error(JrcBackoffice::DocumentSafety::NotClean)
    [-> { bundle.update!(source_digest: '0' * 64) }, -> { bundle.destroy! }].each do |mutation|
      expect(&mutation).to raise_error(ActiveRecord::ReadOnlyRecord)
    end
    expect(domain[:contract].reload.signature_status).not_to eq('signed')
    expect(JrcCrm::AuditEvent.where(account: domain[:account], resource_type: bundle.class.name, resource_id: bundle.id,
                                    event_type: 'backoffice_signature_evidence_captured')).to exist
    expect(bundle.serializable_hash.to_json).not_to include('source_snapshot', 'blob_id', payload[:signed_document],
                                                            delivery.connection.external_account_id)
  end

  it 'replays the same capture without another provider read, duplicate version or changed historical binding' do
    bundle = service.capture!(delivery_id: delivery.id)
    snapshot = bundle.snapshot.deep_dup
    expect(service.capture!(delivery_id: delivery.id).id).to eq(bundle.id)
    expect(gateway).to have_received(:evidence).once
    expect(JrcBackoffice::SignatureArtifactBundle.where(delivery: delivery).count).to eq(1)
    expect(domain[:operation].document_versions.where('document_key LIKE ?', "signature_delivery_#{delivery.id}_%").count).to eq(2)
    expect(bundle.reload.snapshot).to eq(snapshot)
  end

  it 'revalidates native unit access after provider I/O and persists no artifacts or successful capture audit on revocation' do
    original = domain[:operation].document_versions.count
    grant = domain[:account].jrc_crm_user_business_units.find_by!(user: domain[:actor], business_unit: domain[:unit])
    allow(gateway).to receive(:evidence).with(external_id) do
      grant.update!(active: false)
      payload
    end
    expect { service.capture!(delivery_id: delivery.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcBackoffice::SignatureArtifactBundle.where(delivery: delivery)).not_to exist
    expect(domain[:operation].document_versions.count).to eq(original)
    expect(JrcCrm::AuditEvent.where(account: domain[:account], event_type: 'backoffice_signature_evidence_captured')).not_to exist
  end

  it 'rejects cross-account delivery IDs before contacting a provider' do
    account = create(:account)
    account.enable_features!('jrc_crm')
    actor = create(:user, account: account, role: :administrator)
    expect(gateway).not_to receive(:evidence)
    expect do
      described_class.new(account: account, actor: actor, request_id: domain[:operation].id).capture!(delivery_id: delivery.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'serializes two committed captures into one immutable bundle and two native document versions' do
    ready = Queue.new
    gate = Queue.new
    results = Queue.new
    # Both read before either commits; this exercises the real persistence race.
    allow(gateway).to receive(:evidence).with(external_id) do
      ready << true
      gate.pop
      payload.deep_dup
    end
    account_id = domain[:account].id
    actor_id = domain[:actor].id
    request_id = domain[:operation].id
    delivery_id = delivery.id
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          local = described_class.new(account: Account.find(account_id), actor: User.find(actor_id), request_id: request_id)
          results << local.capture!(delivery_id: delivery_id).id
        rescue StandardError => e
          results << e.class.name
        end
      end
    end
    Timeout.timeout(30) { 2.times { ready.pop } }
    2.times { gate << true }
    Timeout.timeout(45) { workers.each(&:join) }
    ids = Array.new(2) { results.pop }
    expect(ids.first).to be_a(Integer)
    expect(ids.uniq.size).to eq(1)
    expect(JrcBackoffice::SignatureArtifactBundle.where(delivery: delivery).count).to eq(1)
    expect(domain[:operation].document_versions.where('document_key LIKE ?', "signature_delivery_#{delivery.id}_%").count).to eq(2)
  ensure
    2.times { gate << true } if gate
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end
