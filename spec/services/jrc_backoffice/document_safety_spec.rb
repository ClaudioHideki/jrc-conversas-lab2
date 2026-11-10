require 'rails_helper'
require 'socket'
require 'timeout'

RSpec.describe JrcBackoffice::DocumentSafety do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:request) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor, contact: contact,
                                                title: 'TESTE SINTÉTICO — Segurança documental', metadata: { required_documents: ['powers'] })
  end
  let(:file) { fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf') }
  let(:version) do
    JrcBackoffice::Documents.new(request: request, actor: actor).upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
  end
  let(:service) { described_class.new(version) }

  before do
    raise 'Disposable candidate database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account.enable_features!('jrc_crm')
  end

  # This is a real Unix-socket protocol exercise, with a simulated daemon
  # reply. It does not demonstrate an installed ClamAV or malware detection.
  def scan_with_reply(reply)
    path = "/run/jrc-bo-av-test-#{SecureRandom.hex(8)}.sock"
    server = UNIXServer.new(path)
    received = Queue.new
    worker = Thread.new { scanner_reply(server, reply, received) }
    result = with_modified_env(JRC_BO_CLAMAV_SOCKET: path) { service.scan! }
    Timeout.timeout(10) { worker.join }
    expect(received.pop).to eq(["zINSTREAM\0", version.sha256])
    result
  ensure
    worker&.kill if worker&.alive?
    server&.close
    File.unlink(path) if path && File.socket?(path)
  end

  def scanner_reply(server, reply, received)
    peer = server.accept
    command = peer.read(10)
    digest = Digest::SHA256.new
    loop do
      length = peer.read(4).unpack1('N')
      break if length.zero?

      digest.update(peer.read(length))
    end
    received << [command, digest.hexdigest]
    peer.write(reply)
  ensure
    peer&.close
  end

  it 'keeps an unavailable scanner in quarantine and ignores client-writable blob scan metadata' do
    version.file.blob.update!(metadata: { service_desk_scan_state: 'clean', service_desk_scan_sha256: version.sha256,
                                          service_desk_scan_adapter: 'clamav-instream-v1', service_desk_scanned_at: Time.current.iso8601 })
    row = with_modified_env(JRC_BO_CLAMAV_SOCKET: nil) { service.scan! }
    expect(row.state).to eq('unavailable')
    expect(row.observed_sha256).to be_nil
    expect { service.bytes! }.to raise_error(described_class::NotClean)
    expect(version.reload.status).to eq('processing')
  end

  it 'records exact streamed bytes and permits their technical read without approving identity or powers' do
    row = scan_with_reply("stream: OK\0")
    expect(row).to be_clean
    expect(row.source_blob_id).to eq(version.file.blob.id)
    expect(service.bytes!).to eq(version.file.download)
    expect(version.reload.analysis).to be_nil
    expect(version.decisions).to be_empty
    expect(version.status).to eq('processing')
    expect { service.scan! }.not_to change(JrcBackoffice::DocumentScan, :count)
  end

  it 'records an infected observation and refuses access to its bytes' do
    row = scan_with_reply("stream: Synthetic.Test FOUND\0")
    expect(row.state).to eq('infected')
    expect { service.bytes! }.to raise_error(described_class::NotClean)
  end

  it 'treats a malformed daemon reply as unavailable' do
    row = scan_with_reply("unexpected reply\0")
    expect(row.state).to eq('unavailable')
    expect(row).not_to be_clean
  end

  it 'checks storage integrity again after a clean observation' do
    scan_with_reply("stream: OK\0")
    blob = version.file.blob
    original = blob.download
    blob.service.upload(blob.key, StringIO.new('%PDF-SYNTHETIC-CHANGED'))
    expect { service.bytes! }.to raise_error(ActiveStorage::IntegrityError)
  ensure
    blob&.service&.upload(blob.key, StringIO.new(original)) if original
  end

  it 'rejects scanning and reading after the source account is deactivated' do
    scan_with_reply("stream: OK\0")
    account.update!(status: 'suspended')
    expect { service.scan! }.to raise_error(Pundit::NotAuthorizedError)
    expect { service.bytes! }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'preserves observations through callbacks and a PostgreSQL immutability trigger' do
    row = scan_with_reply("stream: OK\0")
    expect { row.update!(state: 'infected') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("UPDATE jrc_backoffice_document_scans SET state='infected' WHERE id=#{row.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect(row.reload).to be_clean
  end

  it 'preserves the version attachment and refuses ordinary relinking through callbacks and SQL' do
    attachment = version.file.attachment
    expect { attachment.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      ActiveStorage::Attachment.create!(record: contact, name: 'avatar', blob: version.file.blob)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("DELETE FROM active_storage_attachments WHERE id=#{attachment.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          INSERT INTO active_storage_attachments (name,record_type,record_id,blob_id,created_at)
          VALUES ('avatar','Contact',#{contact.id},#{version.file.blob.id},CURRENT_TIMESTAMP)
        SQL
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /cannot be relinked/)
    expect(version.reload.file.attachment.id).to eq(attachment.id)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("UPDATE jrc_backoffice_document_versions SET document_key='other' WHERE id=#{version.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
  end

  it 'enforces the account/version fence even for a direct SQL insert' do
    row = scan_with_reply("stream: OK\0")
    other = create(:account)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_backoffice_document_scans (account_id,document_version_id,source_blob_id,attempt,state,
            expected_sha256,observed_sha256,scanner_adapter,created_at,updated_at)
          SELECT #{other.id},document_version_id,source_blob_id,99,state,expected_sha256,observed_sha256,
            scanner_adapter,created_at,updated_at FROM jrc_backoffice_document_scans WHERE id=#{row.id}
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey, /bo_document_scan_tenant/)
  end

  it 'does not invoke the parser on quarantined bytes' do
    with_modified_env(JRC_BO_CLAMAV_SOCKET: nil) { service.scan! }
    expect(JrcBackoffice::TextExtraction).not_to receive(:call)
    expect { JrcBackoffice::DocumentPreanalysis.new(version).call }.to raise_error(described_class::NotClean)
  end

  it 'compensates a file when the caller rolls back its outer operation' do
    uploaded = nil
    ApplicationRecord.transaction(requires_new: true) do
      uploaded = version
      raise ActiveRecord::Rollback
    end
    expect(JrcBackoffice::DocumentVersion.exists?(id: uploaded.id)).to be(false)
    expect(uploaded.new_upload_blob.service.exist?(uploaded.new_upload_blob.key)).to be(false)
  end

  it 'removes partial storage bytes and preserves the original storage error' do
    documents = JrcBackoffice::Documents.new(request: request, actor: actor)
    stored = nil
    allow(ActiveStorage::Blob).to receive(:create_after_unfurling!).and_wrap_original do |method, **arguments|
      stored = method.call(**arguments)
    end
    allow(ActiveStorage::Blob.service).to receive(:upload).and_wrap_original do |method, *arguments, **keywords|
      method.call(*arguments, **keywords)
      raise IOError, 'Synthetic storage failure after bytes were written'
    end
    expect do
      documents.upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
    end.to raise_error(IOError, /Synthetic storage failure/)
    expect(request.document_versions.reload).to be_empty
    expect(stored.service.exist?(stored.key)).to be(false)
  end

  it 'rechecks CRM permission after upload I/O and removes the uncommitted file' do
    documents = JrcBackoffice::Documents.new(request: request, actor: actor)
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    stored = nil
    allow(JrcBackoffice::PrivateBlob).to receive(:upload_owned).and_wrap_original do |method, **arguments|
      stored = method.call(**arguments)
      AccountUser.find_by!(account: account, user: actor).update!(custom_role: role)
      stored
    end
    expect do
      documents.upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(request.document_versions.reload).to be_empty
    expect(stored.service.exist?(stored.key)).to be(false)
  end
end
