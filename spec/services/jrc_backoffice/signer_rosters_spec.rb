require 'rails_helper'
require Rails.root.join('db/migrate/20261102070000_create_backoffice_signer_rosters')

RSpec.describe JrcBackoffice::SignerRosters do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:customer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente', relationship_type: 'customer') }
  let(:issuer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Emitente', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade', code: 'SYNTHETIC', company_id: issuer.id) }
  let(:customer_person) do
    create(:contact, account: account, company_id: customer.id, name: 'TESTE SINTÉTICO — Cliente assinante', email: 'customer.signer@example.test')
  end
  let(:issuer_person) do
    create(:contact, account: account, company_id: issuer.id, name: 'TESTE SINTÉTICO — Emitente assinante', email: 'issuer.signer@example.test')
  end
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: customer_person, business_unit: unit, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: customer_person, business_unit: unit,
                                      content_override: 'TESTE SINTÉTICO — Sem envio ou assinatura externa.')
  end
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: customer_person, business_unit: unit, stage: 'contract',
                                                title: 'TESTE SINTÉTICO — Assinantes canônicos')
  end
  let(:service) { described_class.new(account: account, actor: actor, request_id: operation.id) }
  let(:input) do
    { idempotency_key: SecureRandom.uuid, expected_revision: 0, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract),
      customer_mode: 'single', issuer_mode: 'single', change_reason: 'TESTE SINTÉTICO — Seleção inicial de pessoas.',
      signers: [{ contact_id: customer_person.id, party: 'customer' }, { contact_id: issuer_person.id, party: 'issuer' }] }
  end
  let(:roster) { service.create!(**input) }
  let(:versions) { JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: operation.id) }

  before do
    raise 'Disposable candidate database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    account.enable_features!('jrc_crm', 'jrc_customer_master')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit,
                                                structure_managed: true, active: true)
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(contact_id: customer_person.id,
                                                                                  personal_tax_identifier: '11144477735', expected_revision: 0)
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(contact_id: issuer_person.id,
                                                                                  personal_tax_identifier: '52998224725', expected_revision: 0)
  end

  it 'preserves canonical people and encrypted identifiers without granting powers or sending' do
    previous = contract.attributes.slice('status', 'signature_status', 'signed_at', 'signed_by_name')
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    record = roster
    expect(record.snapshot.fetch('signers').pluck('contact_id')).to eq([customer_person.id, issuer_person.id])
    expect(record.snapshot.fetch('signers').pluck('required')).to eq([true, true])
    expect(record.snapshot.dig('signers', 0, 'identity_revision')).to eq(1)
    expect(contract.reload.attributes.slice(*previous.keys)).to eq(previous)
    audit = account.jrc_crm_audit_events.find_by!(event_type: 'backoffice_signer_roster_created', resource_id: operation.id)
    expect(audit.metadata).to include('signing_authority_verified' => false, 'external_delivery' => false)
  end

  it 'omits full identifiers from its DTO/audit and encrypts them in PostgreSQL' do
    record = roster
    expect(record.serializable_hash.to_json).not_to include('11144477735', '52998224725', 'identity_id', 'lookup_digest')
    encrypted = ApplicationRecord.connection.select_value("SELECT source_snapshot FROM jrc_backoffice_signer_rosters WHERE id=#{record.id}")
    expect(encrypted).not_to include('11144477735', '52998224725', customer_person.email)
    audit = account.jrc_crm_audit_events.find_by!(event_type: 'backoffice_signer_roster_created', resource_id: operation.id)
    expect(audit.to_json).not_to include('11144477735', '52998224725')
  end

  it 'replays the same acknowledged intent and rejects stale or altered intent reuse' do
    record = roster
    expect(service.create!(**input).id).to eq(record.id)
    expect { service.create!(**input, change_reason: 'Different action') }.to raise_error(described_class::Changed)
    expect { service.create!(**input, idempotency_key: SecureRandom.uuid) }.to raise_error(described_class::Changed)
    expect(service.scope.count).to eq(1)
  end

  it 'requires a new immutable revision after canonical people change and preserves the old identity' do
    original = roster
    customer_person.update!(name: 'TESTE SINTÉTICO — Nome corrigido')
    revised = service.create!(
      **input, idempotency_key: SecureRandom.uuid, expected_revision: 1,
               expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload), change_reason: 'Correção cadastral autorizada.'
    )
    expect(revised.revision).to eq(2)
    expect(revised.snapshot.dig('signers', 0, 'name')).to eq(customer_person.name)
    expect(original.reload.snapshot.dig('signers', 0, 'name')).to eq('TESTE SINTÉTICO — Cliente assinante')
    expect(original.source_digest).not_to eq(revised.source_digest)
  end

  it 'enforces both sides and all people in a proposed joint rule' do
    expect { service.create!(**input, customer_mode: 'joint') }.to raise_error(ArgumentError, /conjunta/)
    extra = create(:contact, account: account, company_id: customer.id, email: 'joint.signer@example.test')
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(contact_id: extra.id,
                                                                                  personal_tax_identifier: '12345678909', expected_revision: 0)
    selections = input[:signers] + [{ contact_id: extra.id, party: 'customer', required: false, unit_id: 999, account_id: 999 }]
    record = service.create!(**input, customer_mode: 'joint', signers: selections)
    expect(record.customer_mode).to eq('joint')
    expect(record.snapshot.fetch('signers').pluck('required')).to eq([true, true, true])
    expect(record.snapshot.fetch('account_id')).to eq(account.id)
    expect(record.snapshot.fetch('business_unit_id')).to eq(unit.id)
  end

  it 'rejects another company or tenant even when the caller supplies matching spoofed company fields' do
    other_company = account.master_companies.create!(name: 'TESTE SINTÉTICO — Empresa fora do contrato')
    other_person = create(:contact, account: account, company_id: other_company.id)
    selections = [{ contact_id: other_person.id, party: 'customer', company_id: customer.id }, input[:signers].last]
    expect { service.create!(**input, signers: selections) }.to raise_error(ActiveRecord::RecordNotFound)
    foreign = create(:contact, account: create(:account))
    expect do
      service.create!(**input, signers: [{ contact_id: foreign.id, party: 'customer' }, input[:signers].last])
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(service.scope).to be_empty
  end

  it 'never accepts an internal User reference as the customer contact or a duplicated person' do
    expect do
      service.create!(**input, signers: [{ user_id: actor.id, party: 'customer' }, input[:signers].last])
    end.to raise_error(ArgumentError)
    expect do
      service.create!(**input, signers: [input[:signers].first, input[:signers].first])
    end.to raise_error(ArgumentError, /duas posições/)
  end

  it 'refuses missing protected identity, invalid email and blocked people' do
    missing = create(:contact, account: account, company_id: customer.id, email: 'missing.identity@example.test')
    expect do
      service.create!(**input, signers: [{ contact_id: missing.id, party: 'customer' }, input[:signers].last])
    end.to raise_error(ArgumentError, /CPF protegido/)
    customer_person.update!(email: nil)
    expect do
      service.create!(**input, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload))
    end.to raise_error(ArgumentError, /e-mail válido/)
    customer_person.update!(email: 'synthetic.signer@example.test', blocked: true)
    expect do
      service.create!(**input, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload))
    end.to raise_error(ArgumentError, /e-mail válido/)
  end

  it 'rejects legal source changes, sent contracts and terminal operational requests' do
    old_input = input
    contract.update!(content_override: 'TESTE SINTÉTICO — Minuta alterada por outro editor.')
    expect { service.create!(**old_input) }.to raise_error(described_class::Changed)
    contract.update!(signature_status: 'sent')
    expect { service.create!(**old_input) }.to raise_error(ArgumentError, /enviado/)
    operation.update!(status: 'canceled')
    expect { service.create!(**old_input) }.to raise_error(ArgumentError, /Reabra/)
  end

  it 'refuses an unassigned agent, another account and a revoked directory permission' do
    agent = create(:user, account: account, role: :agent)
    outsider = described_class.new(account: account, actor: agent, request_id: operation.id)
    expect { outsider.create!(**input) }.to raise_error(ActiveRecord::RecordNotFound)
    other = described_class.new(account: create(:account), actor: actor, request_id: operation.id)
    expect { other.create!(**input) }.to raise_error(Pundit::NotAuthorizedError)
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    expect { service.create!(**input) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'keeps historical proposals immutable through callbacks and the database' do
    record = roster
    expect { record.update!(change_reason: 'overwrite') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("UPDATE jrc_backoffice_signer_rosters SET revision=99 WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect(record.reload.revision).to eq(1)
  end

  it 'allows an assigned analyst with contact permission and only the required unit coverage' do
    analyst = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[jrc_crm contact_manage])
    AccountUser.find_by!(account: account, user: analyst).update!(custom_role: role)
    account.jrc_crm_user_business_units.create!(user: analyst, scope: 'BUSINESS_UNIT', company: issuer,
                                                business_unit: unit, structure_managed: true, active: true)
    operation.update!(owner: analyst)
    scoped = described_class.new(account: account, actor: analyst, request_id: operation.id)
    result = scoped.create!(**input)
    expect(result.created_by_id).to eq(analyst.id)
    expect(result.snapshot.fetch('business_unit_id')).to eq(unit.id)
    expect(result.snapshot.fetch('signers').pluck('contact_id')).to eq([customer_person.id, issuer_person.id])
  end

  it 'denies even an administrator after its organizational coverage is removed' do
    previous = roster
    account.jrc_crm_user_business_units.structure_managed.where(user_id: actor.id).destroy_all
    expect { service.scope }.to raise_error(ActiveRecord::RecordNotFound)
    expect { service.create!(**input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(previous.reload.revision).to eq(1)
  end

  it 'pins the exact roster in the encrypted contract version and renders every required PDF signature slot' do
    selected = roster
    version = versions.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: versions.source_digest(contract.id),
                               change_reason: 'TESTE SINTÉTICO — Minuta com assinantes definidos.')
    expect(version).to have_attributes(source_format_version: 2, signer_roster_id: selected.id)
    expect(version.snapshot.dig('signer_roster', 'source')).to eq(selected.snapshot)
    extracted = version.pdf_blob.open { |file| JrcBackoffice::TextExtraction.call(file.path, 'application/pdf').fetch(:text) }
    expect(extracted).to include(customer_person.name, issuer_person.name, '11144477735', '52998224725')
    selected.snapshot.fetch('signers').each do |person|
      expect(extracted.scan(person.fetch('anchor')).length).to eq(1)
    end
    expect(Digest::SHA256.hexdigest(version.pdf_blob.download)).to eq(version.pdf_sha256)
    expect(contract.reload.signature_status).not_to eq('signed')
  end

  it 'refuses to generate a new PDF with a stale selected identity or company' do
    roster
    customer_person.update!(name: 'TESTE SINTÉTICO — Alteração posterior à seleção')
    expect do
      versions.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: versions.source_digest(contract.id),
                       change_reason: 'TESTE SINTÉTICO — Não aceitar assinante desatualizado.')
    end.to raise_error(ArgumentError, /dados dos assinantes mudaram/)
    expect(JrcBackoffice::ContractVersion.where(contract: contract)).to be_empty
  end

  it 'keeps old PDFs and masks protected identifiers in actual version comparisons after a new roster' do
    first_roster = roster
    first = versions.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: versions.source_digest(contract.id),
                             change_reason: 'TESTE SINTÉTICO — Primeira seleção.')
    customer_person.update!(name: 'TESTE SINTÉTICO — Nome revisado no cadastro')
    revised = service.create!(**input, idempotency_key: SecureRandom.uuid, expected_revision: 1,
                                       expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                       change_reason: 'Revisar a seleção após mudança cadastral.')
    second = versions.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: versions.source_digest(contract.id),
                              change_reason: 'TESTE SINTÉTICO — Segunda seleção.')
    comparison = versions.differences(second.id).to_json
    expect(comparison).to include(customer_person.name, 'personal_tax_identifier_masked')
    expect(comparison).not_to include('11144477735', '52998224725', '"identity_id"')
    expect(first.reload.signer_roster_id).to eq(first_roster.id)
    expect(second.signer_roster_id).to eq(revised.id)
    expect(Digest::SHA256.hexdigest(versions.download!(first.id).last)).to eq(first.pdf_sha256)
  end

  it 'enforces the tenant fence for the immutable proposal even through a direct SQL insert' do
    record = roster
    foreign = create(:account)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_backoffice_signer_rosters (account_id,contract_id,backoffice_request_id,created_by_id,revision,
            customer_mode,issuer_mode,idempotency_key,source_digest,input_digest,change_reason,source_snapshot,created_at,updated_at)
          SELECT #{foreign.id},contract_id,backoffice_request_id,created_by_id,99,customer_mode,issuer_mode,'foreign-roster-intent',
            source_digest,input_digest,change_reason,source_snapshot,created_at,updated_at
          FROM jrc_backoffice_signer_rosters WHERE id=#{record.id}
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey, /bo_signer_roster_contract_tenant/)
    expect(record.reload.account_id).to eq(account.id)
  end

  it 'refuses a destructive rollback after a roster is preserved and retains the exact version and PDF' do
    preserved = roster
    version = versions.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: versions.source_digest(contract.id),
                               change_reason: 'TESTE SINTÉTICO — Versão com assinantes preservados.')
    expect { CreateBackofficeSignerRosters.new.migrate(:down) }
      .to raise_error(ActiveRecord::IrreversibleMigration, /Preserve signer rosters/)
    expect(preserved.reload.source_digest).to eq(version.reload.snapshot.dig('signer_roster', 'source_digest'))
    expect(Digest::SHA256.hexdigest(version.pdf_blob.download)).to eq(version.pdf_sha256)
  end
end
