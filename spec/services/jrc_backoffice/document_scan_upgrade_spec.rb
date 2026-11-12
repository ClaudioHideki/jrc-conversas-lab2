require 'rails_helper'
require Rails.root.join('db/migrate/20261102060000_create_backoffice_document_scans')

RSpec.describe JrcBackoffice::DocumentScan do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor, contact: contact,
                                                title: 'TESTE SINTÉTICO — Migração documental', metadata: { required_documents: ['powers'] })
  end
  let(:file) { fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf') }
  let(:version) do
    JrcBackoffice::Documents.new(request: operation, actor: actor).upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
  end

  before do
    raise 'Disposable candidate database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account.enable_features!('jrc_crm')
  end

  it 'roundtrips an unused extension and its SQL file without modifying native records or files' do
    previous = [version.reload.attributes, operation.reload.attributes, contact.reload.attributes]
    bytes = version.file.download
    counts = [Account.count, Contact.count, JrcBackoffice::DocumentVersion.count, ActiveStorage::Blob.count]
    CreateBackofficeDocumentScans.new.migrate(:down)
    CreateBackofficeDocumentScans.new.migrate(:up)
    expect([version.reload.attributes, operation.reload.attributes, contact.reload.attributes]).to eq(previous)
    expect(version.file.download).to eq(bytes)
    expect([Account.count, Contact.count, JrcBackoffice::DocumentVersion.count, ActiveStorage::Blob.count]).to eq(counts)
  ensure
    ActiveRecord::Base.connection.schema_cache.clear!
    described_class.reset_column_information
  end

  it 'refuses rollback after an observation exists and preserves the source PDF' do
    record = with_modified_env(JRC_BO_CLAMAV_SOCKET: nil) { JrcBackoffice::DocumentSafety.new(version).scan! }
    expect { CreateBackofficeDocumentScans.new.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /Preserve/)
    expect(record.reload.state).to eq('unavailable')
    expect(Digest::SHA256.hexdigest(version.file.download)).to eq(version.sha256)
  end

  it 'refuses a version attached to a request from another account through SQL' do
    source = version
    other = create(:account)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_backoffice_document_versions (account_id,backoffice_request_id,uploaded_by_id,document_key,
            version,sha256,idempotency_key,created_at,updated_at)
          SELECT #{other.id},backoffice_request_id,uploaded_by_id,document_key,99,sha256,'foreign-request-test',created_at,updated_at
          FROM jrc_backoffice_document_versions WHERE id=#{source.id}
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey, /bo_document_request_tenant/)
  end
end
