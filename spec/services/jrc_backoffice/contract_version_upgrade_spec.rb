require 'rails_helper'
require Rails.root.join('db/migrate/20261102050000_create_backoffice_contract_versions')
require Rails.root.join('db/migrate/20261102060000_create_backoffice_document_scans')
require Rails.root.join('db/migrate/20261102070000_create_backoffice_signer_rosters')
require Rails.root.join('db/migrate/20261102080000_create_backoffice_authority_proposals')

RSpec.describe JrcBackoffice::ContractVersion do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:contract) { account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: contact, content_override: 'TESTE SINTÉTICO') }
  let(:request) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: contact, title: 'TESTE SINTÉTICO — Migração contratual', stage: 'contract')
  end

  before do
    raise 'Disposable database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account.enable_features!('jrc_crm')
  end

  it 'roundtrips an unused extension without changing native contracts, requests or customers' do
    original = [contract.reload.attributes, request.reload.attributes, contact.reload.attributes]
    counts = [Account.count, Contact.count, JrcCrm::Contract.count, JrcCrm::BackofficeRequest.count]
    # The newer document fence references the version extension's tenant index.
    # Roll back dependent extensions first, as the real migration stack does.
    CreateBackofficeAuthorityProposals.new.migrate(:down)
    CreateBackofficeSignerRosters.new.migrate(:down)
    CreateBackofficeDocumentScans.new.migrate(:down)
    CreateBackofficeContractVersions.new.migrate(:down)
    CreateBackofficeContractVersions.new.migrate(:up)
    CreateBackofficeDocumentScans.new.migrate(:up)
    CreateBackofficeSignerRosters.new.migrate(:up)
    CreateBackofficeAuthorityProposals.new.migrate(:up)
    expect([contract.reload.attributes, request.reload.attributes, contact.reload.attributes]).to eq(original)
    expect([Account.count, Contact.count, JrcCrm::Contract.count, JrcCrm::BackofficeRequest.count]).to eq(counts)
  ensure
    CreateBackofficeContractVersions.new.migrate(:up) unless ActiveRecord::Base.connection.table_exists?(:jrc_backoffice_contract_versions)
    CreateBackofficeDocumentScans.new.migrate(:up) unless ActiveRecord::Base.connection.table_exists?(:jrc_backoffice_document_scans)
    CreateBackofficeSignerRosters.new.migrate(:up) unless ActiveRecord::Base.connection.table_exists?(:jrc_backoffice_signer_rosters)
    CreateBackofficeAuthorityProposals.new.migrate(:up) unless ActiveRecord::Base.connection.table_exists?(:jrc_backoffice_authority_proposals)
    ActiveRecord::Base.connection.schema_cache.clear!
    described_class.reset_column_information
  end

  it 'refuses a destructive rollback once a version exists and keeps its PDF' do
    record = JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: request.id).create!(
      idempotency_key: SecureRandom.uuid, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
      change_reason: 'Minuta de teste'
    )
    digest = record.pdf_sha256
    expect { CreateBackofficeContractVersions.new.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /Preserve contract versions/)
    expect(Digest::SHA256.hexdigest(record.reload.pdf_blob.download)).to eq(digest)
  end
end
