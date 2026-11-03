require 'rails_helper'
require 'base64'

# Committed fixtures need explicit cleanup even when the example raises before its normal end.
# rubocop:disable RSpec/InstanceVariable
RSpec.describe JrcMigrations::StorageCompensation do # rubocop:disable RSpec/SpecFilePathFormat
  self.use_transactional_tests = false

  before do
    @account = create(:account)
    @admin = create(:user, account: @account, role: :administrator)
    @project = JrcProjects::Project.create!(account: @account, owner: @admin, key: 'ROLLBACK', name: 'Physical rollback')
    @service = ActiveStorage::Blob.service
    @uploaded_keys = []
    bytes = "%PDF-1.4\nSynthetic rollback fixture\n%%EOF\n".b
    @native_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'keep.pdf', content_type: 'application/pdf')
    @project.attachments.attach(@native_blob)
    row = { 'legacy_id' => 'rollback-file', 'project_id' => @project.id, 'filename' => 'history.pdf', 'content_type' => 'application/pdf',
            'file_base64' => Base64.strict_encode64(bytes), 'file_sha256' => Digest::SHA256.hexdigest(bytes), 'file_size' => bytes.bytesize,
            'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2021-01-02T12:00:00Z' }
    @batch = JrcMigrations::Stage.new(account: @account, user: @admin).call(source: 'rollback_fixture', domain: 'project_attachments', rows: [row],
                                                                            mapping: {})
    JrcMigrations::Preview.new(batch: @batch, user: @admin).call
    allow(@service).to receive(:upload).and_wrap_original do |original, key, *args, **kwargs|
      @uploaded_keys << key
      original.call(key, *args, **kwargs)
    end
    allow(JrcMigrations::Event).to receive(:record!).and_wrap_original do |original, **arguments|
      raise IOError, 'Synthetic final audit failure' if arguments[:action] == 'EXECUTED'

      original.call(**arguments)
    end
  end

  after do
    allow(@service).to receive(:delete).and_call_original
    @uploaded_keys.each { |key| @service.delete(key) }
    @native_blob&.purge
    JrcMigrations::Mapping.where(account: @account).delete_all
    JrcMigrations::Item.where(account: @account).delete_all
    JrcMigrations::Batch.where(account: @account).delete_all # Events cascade through their append-only guard.
    @project&.reload&.destroy!
    @account&.destroy!
    @admin&.destroy!
  end

  def fail_final_event
    expect { JrcMigrations::Execute.new(batch: @batch, user: @admin).call }.to raise_error(IOError, 'Synthetic final audit failure')
    expect_database_rollback
    expect_native_keep
  end

  def expect_database_rollback
    expect(@uploaded_keys.size).to eq(1)
    expect(@batch.reload.status).to eq('previewed')
    expect(@batch.events.where(action: 'EXECUTED')).to be_empty
    expect(ActiveStorage::Blob.where(key: @uploaded_keys)).to be_empty
    expect(JrcMigrations::Mapping.where(account: @account)).to be_empty
  end

  def expect_native_keep
    expect(@project.attachments_attachments.reload.pluck(:blob_id)).to eq([@native_blob.id])
    expect(@native_blob.service.exist?(@native_blob.key)).to be(true)
  end

  it 'removes only the new physical file after the final audit fails and preserves the preexisting native file' do
    fail_final_event
    expect(@service.exist?(@uploaded_keys.sole)).to be(false)
  end

  it 'persists a private cleanup reference outside the failed transaction when storage deletion fails' do
    allow(@service).to receive(:delete).and_raise(IOError, 'Synthetic delete outage')
    fail_final_event
    key = @uploaded_keys.sole
    expect(@service.exist?(key)).to be(true)
    cleanup = @batch.items.reload.sole.before_data.fetch('storage_cleanup').sole
    expect(cleanup).to include('service_name' => @native_blob.service_name, 'blob_key' => key)
    expect(cleanup.fetch('sha256')).to match(/\A[a-f0-9]{64}\z/)
  end

  it 'promotes compensation beyond item savepoints when a caller transaction fails after execute returns' do
    allow(JrcMigrations::Event).to receive(:record!).and_call_original
    expect do
      ActiveRecord::Base.transaction do
        JrcMigrations::Execute.new(batch: @batch, user: @admin).call
        expect(@batch.items.reload.sole.status).to eq('applied')
        raise IOError, 'Synthetic caller rollback'
      end
    end.to raise_error(IOError, 'Synthetic caller rollback')
    expect(@uploaded_keys.size).to eq(1)
    expect(@service.exist?(@uploaded_keys.sole)).to be(false)
    expect(@batch.reload.status).to eq('previewed')
    expect(@native_blob.service.exist?(@native_blob.key)).to be(true)
  end
end
# rubocop:enable RSpec/InstanceVariable
