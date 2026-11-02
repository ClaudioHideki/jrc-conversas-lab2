require 'rails_helper'
require 'timeout'

RSpec.describe JrcBackoffice::ContractVersions do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:contract) { account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: contact, content_override: 'TESTE SINTÉTICO') }
  let(:request) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: contact, title: 'TESTE SINTÉTICO — Concorrência contratual', stage: 'contract',
                                                metadata: {
                                                  document_checklist: [{ key: 'supporting', source: 'manual', required: false, blocking: false }]
                                                })
  end
  let(:input) do
    { idempotency_key: SecureRandom.uuid, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
      change_reason: 'Revisão sintética simultânea' }
  end

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Dedicated disposable database required' unless Rails.env.test? && config.database == 'jrc_four_domains_schema_test' &&
                                                          config.host == 'jrc-rel-v2-pg-20261101'

    account.enable_features!('jrc_crm')
    request
    input
  end

  def generate_version
    described_class.new(account: Account.find(account.id), actor: User.find(actor.id), request_id: request.id).create!(**input).id
  end

  it 'serializes the same intent on independent PostgreSQL connections into one version and PDF' do
    ready = Queue.new
    start = Queue.new
    results = Queue.new
    threads = Array.new(2) do
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          results << generate_version
        rescue StandardError => e
          results << e
        end
      end
    end
    Timeout.timeout(30) do
      expect(Array.new(2) { ready.pop }.uniq.length).to eq(2)
      2.times { start << true }
      threads.each(&:join)
      values = Array.new(2) { results.pop }
      expect(values).to all(be_a(Integer)), values.inspect
      expect(values.uniq.length).to eq(1)
    end
    rows = JrcBackoffice::ContractVersion.where(contract: contract)
    expect(rows.count).to eq(1)
    expect(Digest::SHA256.hexdigest(rows.first.pdf_blob.download)).to eq(rows.first.pdf_sha256)
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  it 'allows native document FK/audit inserts while generation holds the account and waits for the request' do
    locked = Queue.new
    upload = Queue.new
    generator = Queue.new
    results = Queue.new
    reader = nil
    writer = Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        source = JrcCrm::BackofficeRequest.find(request.id)
        source.with_lock do
          locked << connection.select_value('SELECT pg_backend_pid()')
          upload.pop
          file = fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf')
          results << JrcBackoffice::Documents.new(request: source, actor: User.find(actor.id))
                                             .upload!(key: 'supporting', file: file, idempotency_key: SecureRandom.uuid).id
        end
      rescue StandardError => e
        results << e
      end
    end
    Timeout.timeout(30) do
      writer_pid = locked.pop
      reader = Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          generator << connection.select_value('SELECT pg_backend_pid()')
          results << generate_version
        rescue StandardError => e
          results << e
        end
      end
      reader_pid = generator.pop
      expect(reader_pid).not_to eq(writer_pid)
      loop do
        blockers = ApplicationRecord.connection.select_value("SELECT #{writer_pid.to_i} = ANY(pg_blocking_pids(#{reader_pid.to_i}))")
        break if blockers

        sleep 0.01
      end
      upload << true
      [writer, reader].each(&:join)
      values = Array.new(2) { results.pop }
      expect(values).to all(be_a(Integer)), values.inspect
    end
    expect(request.document_versions.count).to eq(1)
    expect(JrcBackoffice::ContractVersion.where(contract: contract).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_document_version_uploaded').count).to eq(1)
  ensure
    [writer, reader].compact.each { |thread| thread.kill if thread.alive? }
  end
end
