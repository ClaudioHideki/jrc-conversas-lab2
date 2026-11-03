require 'base64'

RSpec.shared_context 'JRC migration media fixtures' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:project) { JrcProjects::Project.create!(account: account, owner: admin, key: 'MEDIA_FLOW', name: 'Synthetic media migration', visibility: 'private') }
  let(:bytes) { "%PDF-1.4\nSynthetic durable import\n%%EOF\n".b }
  let(:media_row) do
    { 'legacy_id' => 'durable-file', 'project_id' => project.id, 'filename' => 'source.pdf', 'content_type' => 'application/pdf',
      'file_base64' => Base64.strict_encode64(bytes), 'file_sha256' => Digest::SHA256.hexdigest(bytes), 'file_size' => bytes.bytesize,
      'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2021-01-02T12:00:00Z' }
  end
  let(:batch) do
    JrcMigrations::Stage.new(account: account, user: admin).call(source: 'durable_fixture', domain: 'project_attachments',
                                                               rows: [media_row], mapping: {})
  end

  before { account.enable_features!('data_import', 'jrc_projects') }

  def preview_media
    JrcMigrations::Preview.new(batch: batch, user: admin).call
    batch.items.reload.sole
  end

  def execute_media
    preview_media
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    expect(batch.items.reload.sole.status).to eq('applied')
    project.attachments_attachments.sole.blob
  end

  def media_object
    JrcMigrations::MediaObject.where(account_id: account.id, item_id: batch.items.sole.id).order(:id).last!
  end
end
