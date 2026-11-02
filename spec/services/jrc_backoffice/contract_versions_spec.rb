require 'rails_helper'

RSpec.describe JrcBackoffice::ContractVersions do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, email: 'contract-version@example.test') }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: contact, content_override: 'TESTE SINTÉTICO — Minuta original.')
  end
  let(:request) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: contact, title: 'TESTE SINTÉTICO — Versão contratual', stage: 'contract',
                                                metadata: { contract_required: true })
  end
  let(:service) { described_class.new(account: account, actor: actor, request_id: request.id) }
  let(:key) { SecureRandom.uuid }
  let(:source) { JrcBackoffice::ContractSnapshot.digest(contract.reload) }
  let(:version) { service.create!(idempotency_key: key, expected_source_digest: source, change_reason: 'Minuta inicial para revisão') }

  before { account.enable_features!('jrc_crm') }

  it 'stores the native PDF, exact legal source and checksum without changing signature facts' do
    expect(version.pdf_blob.download).to start_with('%PDF-')
    expect(Digest::SHA256.hexdigest(version.pdf_blob.download)).to eq(version.pdf_sha256)
    expect(version.snapshot.dig('contract', 'content_override')).to eq(contract.content_override)
    raw = ActiveRecord::Base.connection.select_value("SELECT source_snapshot FROM jrc_backoffice_contract_versions WHERE id=#{version.id}")
    expect(raw).not_to include('Minuta original', contact.email)
    expect(version.serializable_hash.keys).not_to include('source_snapshot', 'pdf_blob_id')
    expect(contract.reload.signature_status).to eq('not_started')
    expect(request.reload.stage).to eq('contract')
  end

  it 'reuses an intent on retry and refuses reuse with a different source or reason' do
    first = version
    expect(service.create!(idempotency_key: key, expected_source_digest: first.source_digest, change_reason: first.change_reason).id).to eq(first.id)
    expect(JrcBackoffice::ContractVersion.where(contract: contract).count).to eq(1)
    expect { service.create!(idempotency_key: key, expected_source_digest: first.source_digest, change_reason: 'Outra revisão') }
      .to raise_error(JrcBackoffice::ContractVersions::Changed)
  end

  it 'keeps the old PDF and exposes actual changes after an authorized legal edit' do
    first = version
    original = first.pdf_blob.download
    contract.update!(content_override: 'TESTE SINTÉTICO — Cláusula revisada.')
    second = service.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                             change_reason: 'Revisão de cláusula')
    expect(second.number).to eq(2)
    expect(first.reload.pdf_blob.download).to eq(original)
    expect(second.pdf_sha256).not_to eq(first.pdf_sha256)
    expect(service.differences(second.id)).to include(path: 'contract.content_override', before: first.snapshot.dig('contract', 'content_override'),
                                                      after: contract.content_override)
    expect(second.change_paths).to include('contract.content_override')
  end

  it 'rejects a stale preview without creating any document or version' do
    previous = source
    contract.update!(notes: 'Alterada por outro operador')
    expect do
      service.create!(idempotency_key: key, expected_source_digest: previous, change_reason: 'Prévia antiga')
    end.to raise_error(JrcBackoffice::ContractVersions::Changed)
    expect(JrcBackoffice::ContractVersion.count).to eq(0)
  end

  it 'detects a source change during native PDF rendering' do
    expect(JrcCrm::ContractPdfService).to receive(:new).with(contract, revision: 1).and_wrap_original do |method, *args, **kwargs|
      renderer = method.call(*args, **kwargs)
      allow(renderer).to receive(:call).and_wrap_original do |render|
        data = render.call
        contract.update!(content_override: 'Alteração concorrente de teste')
        data
      end
      renderer
    end
    expect { version }.to raise_error(JrcBackoffice::ContractVersions::Changed)
    expect(JrcBackoffice::ContractVersion.count).to eq(0)
  end

  it 'refuses a foreign account, an unassigned agent and a revoked membership' do
    request
    foreign = create(:account)
    expect { described_class.new(account: foreign, actor: actor, request_id: request.id).scope }.to raise_error(Pundit::NotAuthorizedError)
    agent = create(:user, account: account, role: :agent)
    expect { described_class.new(account: account, actor: agent, request_id: request.id).scope }.to raise_error(ActiveRecord::RecordNotFound)
    AccountUser.where(account: account, user: actor).delete_all
    expect { service.scope }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'allows the assigned Backoffice analyst without granting every contract in CRM' do
    agent = create(:user, account: account, role: :agent)
    request.update!(owner: agent)
    scoped = described_class.new(account: account, actor: agent, request_id: request.id)
    record = scoped.create!(idempotency_key: key, expected_source_digest: source, change_reason: 'Revisão pelo analista atribuído')
    expect(record.created_by_id).to eq(agent.id)
    expect(contract.reload.owner_id).to eq(actor.id)
  end

  it 'requires actual document decisions for v2 rather than caller-supplied approved metadata' do
    request.update!(metadata: { required_documents: ['representation'], document_statuses: { representation: 'approved' } })
    expect { version }.to raise_error(ArgumentError, /documentação obrigatória/)
    expect(JrcBackoffice::ContractVersion.count).to eq(0)
  end

  it 'preserves signed history and refuses generating a replacement through this draft route' do
    file = Rails.root.join('spec/fixtures/files/sample.pdf')
    contract.signed_document.attach(io: File.open(file), filename: 'synthetic.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_by_name: 'TESTE SINTÉTICO', signed_at: Time.current)
    expect { version }.to raise_error(ArgumentError, /Preserve o contrato enviado ou assinado/)
    expect(contract.reload.signature_status).to eq('signed')
  end

  it 'refuses completed requests without mutating their history' do
    ActiveRecord::Base.connection.execute("UPDATE jrc_crm_backoffice_requests SET status='completed' WHERE id=#{request.id}")
    expect { version }.to raise_error(ArgumentError, /Reabra/)
    expect(JrcBackoffice::ContractVersion.count).to eq(0)
  end

  it 'pins all version fields in the database and preserves the tenant foreign keys' do
    record = version
    expect do
      JrcBackoffice::ContractVersion.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("UPDATE jrc_backoffice_contract_versions SET number=99 WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Contract versions are immutable/)
    expect do
      JrcBackoffice::ContractVersion.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("DELETE FROM jrc_backoffice_contract_versions WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /Contract versions are immutable/)
    expect(record.reload.number).to eq(1)
    foreign = create(:account)
    expect do
      JrcBackoffice::ContractVersion.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_backoffice_contract_versions
            (account_id,backoffice_request_id,contract_id,created_by_id,pdf_blob_id,number,source_format_version,
             idempotency_key,source_digest,pdf_sha256,source_snapshot,change_reason,change_paths,created_at,updated_at)
          SELECT #{foreign.id},backoffice_request_id,contract_id,created_by_id,pdf_blob_id,99,source_format_version,
                 'foreign-test-intent',source_digest,pdf_sha256,source_snapshot,change_reason,change_paths,created_at,updated_at
          FROM jrc_backoffice_contract_versions WHERE id=#{record.id}
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'checks the file checksum and revalidates permission on download' do
    record = version
    expect(service.download!(record.id).last).to eq(record.pdf_blob.download)
    allow(record.pdf_blob.service).to receive(:download).with(record.pdf_blob.key).and_return('%PDF-TAMPERED')
    expect { service.download!(record.id) }.to raise_error(ActiveStorage::IntegrityError)
    AccountUser.where(account: account, user: actor).delete_all
    expect { service.download!(record.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not return file bytes or record an access after membership is revoked during storage I/O' do
    record = version
    allow(record.pdf_blob.service).to receive(:download).with(record.pdf_blob.key).and_wrap_original do |method, *arguments|
      bytes = method.call(*arguments)
      ActiveRecord::Base.connection.execute("DELETE FROM account_users WHERE account_id=#{account.id} AND user_id=#{actor.id}")
      bytes
    end
    expect { service.download!(record.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcCrm::AuditEvent.where(event_type: 'backoffice_contract_version_accessed', resource_id: record.id)).not_to exist
  end

  it 'removes only its uncommitted PDF if persistence fails and preserves the original error' do
    uploaded = nil
    allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_wrap_original do |method, **attributes|
      uploaded = method.call(**attributes)
    end
    allow(JrcCrm::AuditEvent).to receive(:create!).and_wrap_original do |method, attributes|
      raise 'synthetic audit failure' if attributes[:event_type] == 'backoffice_contract_version_created'

      method.call(attributes)
    end
    expect { version }.to raise_error(RuntimeError, 'synthetic audit failure')
    expect(JrcBackoffice::ContractVersion.count).to eq(0)
    expect(uploaded.service.exist?(uploaded.key)).to be(false)
  end

  it 'uses the current human document decision and does not carry it to a replacement file' do
    request.update!(metadata: { required_documents: ['representation'] })
    documents = JrcBackoffice::Documents.new(request: request, actor: actor)
    file = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf')
    first = documents.upload!(key: 'representation', file: file, idempotency_key: SecureRandom.uuid)
    first.create_analysis!(analyzer_version: 'synthetic-document-fixture/1', state: 'review_required', evidence: {})
    documents.decide!(version: first, status: 'approved', reason: 'TESTE SINTÉTICO — Documento conferido por pessoa autorizada')
    expect(version.number).to eq(1)
    documents.upload!(key: 'representation', file: file, idempotency_key: SecureRandom.uuid)
    expect do
      service.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: source, change_reason: 'Documento substituído')
    end.to raise_error(ArgumentError, /documentação obrigatória/)
    expect(JrcBackoffice::ContractVersion.where(contract: contract).count).to eq(1)
  end

  it 'cleans the new PDF if a caller rolls back its outer operation' do
    record = nil
    JrcBackoffice::ContractVersion.transaction(requires_new: true) do
      record = version
      raise ActiveRecord::Rollback
    end
    expect(JrcBackoffice::ContractVersion.exists?(id: record.id)).to be(false)
    expect(record.pdf_blob.service.exist?(record.pdf_blob.key)).to be(false)
  end

  it 'renders the canonical company, its identifier and revision without embedding a stale signature status' do
    company = account.master_companies.create!(name: 'EMPRESA SINTETICA CONTRATANTE', tax_id: '11222333000181',
                                               person_kind: 'organization', relationship_type: 'customer')
    contact.update!(company_id: company.id)
    text = version.pdf_blob.open { |file| JrcBackoffice::TextExtraction.call(file.path, 'application/pdf').fetch(:text) }
    expect(text.encoding).to eq(Encoding::UTF_8)
    expect(text).to include(company.name, company.tax_id, 'contratual')
    expect(text).not_to include('not_started', 'Situação da assinatura')
    expect(version.snapshot.dig('customer', 'id')).to eq(company.id)
  end
end
