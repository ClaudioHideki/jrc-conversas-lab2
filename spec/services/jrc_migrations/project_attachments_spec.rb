require 'rails_helper'
require 'base64'

# Integration coverage groups several adapters under the Migration Center feature.
RSpec.describe JrcMigrations::Adapters::ProjectAttachment do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:project) { JrcProjects::Project.create!(account: account, owner: admin, key: 'IMPORT', name: 'Attachment destination') }
  let(:bytes) { "%PDF-1.4\nSynthetic historical attachment\n%%EOF\n".b }
  let(:row) do
    { 'legacy_id' => 'file-1', 'project_id' => project.id, 'filename' => 'original.pdf', 'content_type' => 'application/pdf',
      'file_base64' => Base64.strict_encode64(bytes), 'file_sha256' => Digest::SHA256.hexdigest(bytes), 'file_size' => bytes.bytesize,
      'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2021-01-02T12:00:00Z' }
  end

  def preview(data = row, domain: 'project_attachments')
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(source: 'fixture', domain: domain, rows: [data], mapping: {})
    JrcMigrations::Preview.new(batch: batch, user: admin).call
    batch
  end

  def execute(batch)
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    batch.items.reload.first
  end

  it 'stores and reads back actual bytes under the project without touching its historic dates or enqueuing work' do
    batch = preview
    expect(batch.items.first.decision).to eq('create')
    parent_time = project.reload.updated_at
    expect { execute(batch) }.not_to have_enqueued_job
    attachment = project.attachments_attachments.sole
    file_evidence = { bytes: attachment.blob.download, name: attachment.blob.filename.to_s,
                      sha256: attachment.blob.metadata['migration_sha256'], scan: attachment.blob.metadata['service_desk_scan_state'] }
    expect(file_evidence).to eq(bytes: bytes, name: 'original.pdf', sha256: row['file_sha256'], scan: 'unavailable')
    expect(attachment.created_at).to eq(Time.iso8601(row['created_at']))
    expect(project.reload.updated_at).to eq(parent_time)
    expect(JrcMigrations::Mapping.find_by!(domain: 'project_attachments', target_id: attachment.id).accepted_at).to be_nil
    expect(JrcMigrations::Reconciliation.new(batch: batch, user: admin).call['matched']).to eq(1)
  end

  it 'rejects mismatched bytes or size before writing any attachment' do
    expect { preview(row.merge('file_sha256' => '0' * 64)) }.not_to change(ActiveStorage::Blob, :count)
    expect(preview(row.merge('file_sha256' => '0' * 64)).items.first).to have_attributes(decision: 'reject', error_code: 'ATTACHMENT_HASH_MISMATCH')
    expect(preview(row.merge('file_size' => bytes.bytesize + 1)).items.first.decision).to eq('reject')
  end

  it 'rejects a project belonging to another account and never binds a user supplied polymorphic type' do
    foreign = create(:account)
    owner = create(:user, account: foreign)
    target = JrcProjects::Project.create!(account: foreign, owner: owner, key: 'FOREIGN', name: 'Foreign')
    expect(preview(row.merge('project_id' => target.id)).items.first.decision).to eq('reject')
    execute(preview(row.merge('record_type' => 'User', 'record_id' => admin.id)))
    expect(project.attachments_attachments.sole.record).to eq(project)
  end

  it 'reprocesses an identical source without duplicate blobs and rejects a changed append-only file' do
    first = preview
    execute(first)
    expect { execute(preview) }.not_to change(ActiveStorage::Blob, :count)
    changed_bytes = "#{bytes}changed"
    changed = row.merge('file_base64' => Base64.strict_encode64(changed_bytes), 'file_size' => changed_bytes.bytesize,
                        'file_sha256' => Digest::SHA256.hexdigest(changed_bytes), 'updated_at' => '2022-01-02T12:00:00Z')
    expect(preview(changed).items.first).to have_attributes(decision: 'reject', error_code: 'APPEND_ONLY_DESTINATION')
    expect(project.attachments_attachments.sole.blob.download).to eq(bytes)
  end

  it 'does not certify a persisted attachment whose physical bytes no longer match the staged source' do
    batch = preview
    execute(batch)
    attachment = project.attachments_attachments.sole
    attachment.blob.service.upload(attachment.blob.key, StringIO.new('different stored bytes'))
    report = JrcMigrations::Reconciliation.new(batch: batch, user: admin).call
    expect(report).to include('matched' => 0, 'divergent' => 1)
    expect do
      JrcMigrations::Reconciliation.new(batch: batch, user: admin).accept!(note: 'Must remain blocked')
    end.to raise_error(JrcMigrations::Error, 'RECONCILIATION_REQUIRED')
  end

  it 'binds task files to the actual task and applies account and migration acceptance through the typed attachment scope' do
    task = JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Task with a file')
    batch = preview(row.except('project_id').merge('task_id' => task.id), domain: 'project_task_attachments')
    execute(batch)
    attachment = task.attachments_attachments.sole
    expect(attachment.blob.download).to eq(bytes)
    expect(JrcMigrations::Visibility.allowed?(attachment, account: account, domain: 'project_attachments')).to be(false)
    expect(JrcMigrations::Visibility.allowed?(attachment, account: account, domain: 'project_task_attachments')).to be(false)
    JrcMigrations::Reconciliation.new(batch: batch, user: admin).accept!(note: 'Reviewed synthetic file')
    expect(JrcMigrations::Visibility.allowed?(attachment, account: account, domain: 'project_task_attachments')).to be(true)
    expect(JrcMigrations::Visibility.allowed?(attachment, account: create(:account), domain: 'project_task_attachments')).to be(false)
  end

  it 'retains a private cleanup reference when an interrupted upload cannot be removed and never certifies the row' do
    batch = preview
    service = ActiveStorage::Blob.service
    allow(service).to receive(:upload).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs)
      raise IOError, 'Synthetic lost storage response'
    end
    allow(service).to receive(:delete).and_raise(IOError, 'Synthetic cleanup outage')
    item = execute(batch)
    expect(item).to have_attributes(status: 'failed', error_code: 'ATTACHMENT_CLEANUP_REQUIRED')
    cleanup = item.before_data.fetch('storage_cleanup').sole
    key = cleanup.fetch('blob_key')
    expect(service.exist?(key)).to be(true)
    expect(project.attachments_attachments).to be_empty
    expect(JrcMigrations::Reconciliation.new(batch: batch, user: admin).call).to include('matched' => 0, 'blocked' => 1)
  ensure
    if service && key
      allow(service).to receive(:delete).and_call_original
      service.delete(key)
    end
  end
end
