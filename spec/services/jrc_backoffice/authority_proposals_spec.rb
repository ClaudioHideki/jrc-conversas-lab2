require 'rails_helper'
require Rails.root.join('db/migrate/20261102080000_create_backoffice_authority_proposals')

RSpec.describe JrcBackoffice::AuthorityProposals, :approval_core, :authority_core do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:operation) { domain.fetch(:operation) }
  let(:contract) { domain.fetch(:contract) }
  let(:reviewer) { approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide]) }
  let(:document) { authority_document(domain) }
  let(:roster) { authority_roster(domain) }
  let(:version) do
    document
    roster
    domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(contract.id),
                              change_reason: 'TESTE SINTÉTICO — Minuta com todas as pessoas.')
  end
  let(:policy) { authority_policy(domain, [reviewer]) }
  let(:service) { described_class.new(account: account, actor: actor, request_id: operation.id) }
  let(:input) { authority_input(version, roster, document) }
  let(:proposal) do
    policy
    service.create!(**input)
  end
  let(:approval) do
    JrcApprovals::Request.find_by!(account_id: account.id, resource_type: 'JrcBackoffice::AuthorityProposal', resource_id: proposal.id)
  end

  before do
    raise 'Owned candidate database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    domain
  end

  it 'creates only a sealed proposal and a pending native case, with no provider or operational effect' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    expect(approval.state).to eq('pending')
    expect(approval.snapshot.fetch('values')).to include('signer_count' => 2, 'evidence_state' => 'current')
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call[:status]).to eq('blocked')
    expect(contract.reload.signature_status).to eq('not_started')
    expect(operation.reload.stage).to eq('contract')
    expect(proposal.snapshot.fetch('document_bindings').first).to include('sha256' => document.sha256, 'ready' => true)
  end

  it 'requires native approval even when all CPFs, scans and human document decisions are present' do
    expect { service.create!(**input) }.to raise_error(JrcApprovals::Error, 'POLICY_REQUIRED')
    expect(service.scope).to be_empty
    expect(JrcApprovals::Request.where(account_id: account.id)).to be_empty
  end

  it 'lets the designated legal reviewer decide exact evidence without directory management or Backoffice ownership' do
    record = approval
    expect do
      JrcBackoffice::ContractAccess.new(account: account, actor: reviewer.user).request(operation.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(reviewer.permissions).not_to include('contact_manage')
    approval_vote(domain, reviewer, record)
    status = JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call(verify: true)
    expect(status).to include(status: 'verified', current: true)
    expect(contract.reload.signature_status).to eq('not_started')
    expect(operation.reload.stage).to eq('contract')
  end

  it 'replays exactly the proposal without duplicating cases and rejects altered or competing intents' do
    original = proposal
    expect(service.create!(**input).id).to eq(original.id)
    expect { service.create!(**input, change_reason: 'Changed justification') }.to raise_error(described_class::Changed)
    expect { service.create!(**input, idempotency_key: SecureRandom.uuid) }.to raise_error(described_class::Changed)
    expect(service.scope.count).to eq(1)
    expect(JrcApprovals::Request.where(account_id: account.id).count).to eq(1)
  end

  it 'requires declarations and evidence for every required signer and disallows company representation in own name' do
    policy
    expect { service.create!(**input, proofs: input[:proofs].take(1)) }.to raise_error(ArgumentError, /todos/)
    same = input[:proofs].map { |row| row.merge('signer_key' => input[:proofs].first['signer_key']) }
    expect { service.create!(**input, proofs: same) }.to raise_error(ArgumentError, /única/)
    own = input[:proofs].map { |row| row.merge('basis' => 'self') }
    expect { service.create!(**input, proofs: own) }.to raise_error(ArgumentError, /pessoa física/)
    expect(service.scope).to be_empty
  end

  it 'rejects future, expired and inconsistent representation dates' do
    policy
    expired = input[:proofs].map { |row| row.merge('valid_from' => (Date.current - 5).iso8601, 'valid_until' => (Date.current - 1).iso8601) }
    expect { service.create!(**input, proofs: expired) }.to raise_error(JrcApprovals::Error, 'AUTHORITY_CONTEXT_STALE')
    future = input[:proofs].map { |row| row.merge('valid_from' => (Date.current + 1).iso8601) }
    expect { service.create!(**input, proofs: future) }.to raise_error(JrcApprovals::Error, 'AUTHORITY_CONTEXT_STALE')
    invalid = input[:proofs].map { |row| row.merge('no_expiry' => true) }
    expect { service.create!(**input, proofs: invalid) }.to raise_error(ArgumentError, /Validade/)
    expect(service.scope).to be_empty
  end

  it 'never grants powers to an unassigned administrator or a user in another unit or account' do
    proposal
    outsider = approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide])
    expect do
      JrcBackoffice::AuthoritySource.new(proposal: proposal, actor: outsider.user).current
    end.to raise_error(Pundit::NotAuthorizedError)
    stranger = create(:user, account: create(:account), role: :administrator)
    expect do
      JrcBackoffice::AuthoritySource.new(proposal: proposal, actor: stranger).current
    end.to raise_error(Pundit::NotAuthorizedError)
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    expect { JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call }.to raise_error(Pundit::NotAuthorizedError)
    expect { service.create!(**input) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'invalidates the legal decision after a canonical identity revision without exposing the CPF' do
    record = approval
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(
      contact_id: domain[:customer_person].id, personal_tax_identifier: '12345678909', expected_revision: 1
    )
    expect { approval_vote(domain, reviewer, record) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
    expect(record.reload.decisions).to be_empty
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call[:status]).to eq('blocked')
    expect(proposal.serializable_hash.to_json).not_to include('11144477735', '52998224725', 'identity_id', 'anchor')
  end

  it 'rejects a replaced document even if its bytes match the old document' do
    record = approval
    domain[:documents].upload!(key: 'representation', file: domain[:file], idempotency_key: SecureRandom.uuid)
    expect { approval_vote(domain, reviewer, record) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
    expect(record.reload.decisions).to be_empty
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call[:facts]).to include(documents_current: false)
  end

  it 'checks the physical evidence before accepting a vote even when metadata is unchanged' do
    record = approval
    blob = document.file.blob
    original = blob.download
    blob.service.upload(blob.key, StringIO.new('%PDF-SYNTHETIC-CORRUPTION'))
    expect { approval_vote(domain, reviewer, record) }.to raise_error(JrcApprovals::Error, 'AUTHORITY_EVIDENCE_UNAVAILABLE')
    expect(record.reload.decisions).to be_empty
  ensure
    blob&.service&.upload(blob.key, StringIO.new(original)) if original
  end

  it 'checks the exact contract PDF before accepting a vote' do
    record = approval
    blob = version.pdf_blob
    original = blob.download
    blob.service.upload(blob.key, StringIO.new('%PDF-SYNTHETIC-OTHER-VERSION'))
    expect { approval_vote(domain, reviewer, record) }.to raise_error(JrcApprovals::Error, 'AUTHORITY_EVIDENCE_UNAVAILABLE')
    expect(record.reload.decisions).to be_empty
  ensure
    blob&.service&.upload(blob.key, StringIO.new(original)) if original
  end

  it 'allows an authorized rejection of unavailable evidence without granting representation or accepting a signature' do
    record = approval
    blob = document.file.blob
    original = blob.download
    blob.service.upload(blob.key, StringIO.new('%PDF-SYNTHETIC-UNAVAILABLE-EVIDENCE'))
    vote = approval_vote(domain, reviewer, record, decision: 'rejected', reason: 'TESTE SINTÉTICO — Evidência indisponível para conferência.')
    expect(vote.decision).to eq('rejected')
    expect(record.reload.state).to eq('rejected')
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call(verify: true)[:status]).to eq('blocked')
    expect(contract.reload.signature_status).to eq('not_started')
  ensure
    blob&.service&.upload(blob.key, StringIO.new(original)) if original
  end

  it 'does not read file bytes or mutate state in a native simulation' do
    proposal
    storage = version.pdf_blob.service
    expect(document.file.blob.service).to equal(storage)
    expect(storage).not_to receive(:download)
    expect do
      result = JrcApprovals::Requests.new(account: account, user: actor).simulate(key: JrcBackoffice::AuthorityCatalog::KEY, resource_id: proposal.id)
      expect(result[:effects]).to eq([])
      expect(result[:versions].pluck(:id)).to eq([policy.current_version_id])
    end.not_to change(JrcApprovals::Request, :count)
    expect(approval.state).to eq('pending')
  end

  it 'refuses voting and using old approval after a new contract version exists' do
    record = approval
    approval_vote(domain, reviewer, record)
    domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(contract.id),
                              change_reason: 'TESTE SINTÉTICO — Substituição da versão.')
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call[:status]).to eq('blocked')
    expect(proposal.reload.contract_version_id).to eq(version.id)
  end

  it 'does not fall back to an older approved proposal when a newer proposal is pending' do
    approval_vote(domain, reviewer, approval)
    newer = service.create!(**input, expected_revision: 1, idempotency_key: SecureRandom.uuid, change_reason: 'TESTE SINTÉTICO — Nova comprovação.')
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call[:status]).to eq('blocked')
    expect(JrcBackoffice::AuthorityStatus.new(proposal: newer, actor: actor).call[:status]).to eq('blocked')
    expect(newer.revision).to eq(2)
  end

  it 'preserves sealed proposals through model, SQL and destructive rollback guards' do
    record = proposal
    expect { record.update!(change_reason: 'Mutated') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("UPDATE jrc_backoffice_authority_proposals SET revision=99 WHERE id=#{record.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { CreateBackofficeAuthorityProposals.new.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
    encrypted = ApplicationRecord.connection.select_value("SELECT source_snapshot FROM jrc_backoffice_authority_proposals WHERE id=#{record.id}")
    expect(encrypted).not_to include('legal_representative', document.sha256)
    expect(record.reload.snapshot.fetch('document_bindings').first['sha256']).to eq(document.sha256)
  end

  it 'enforces the exact account, contract, request, roster and version origin even for SQL inserts' do
    record = proposal
    foreign = create(:account)
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute(<<~SQL.squish)
          INSERT INTO jrc_backoffice_authority_proposals (account_id,contract_id,backoffice_request_id,contract_version_id,
            signer_roster_id,created_by_id,revision,idempotency_key,input_digest,source_digest,change_reason,source_snapshot,created_at,updated_at)
          SELECT #{foreign.id},contract_id,backoffice_request_id,contract_version_id,signer_roster_id,created_by_id,99,
            'foreign-authority-origin',input_digest,source_digest,change_reason,source_snapshot,created_at,updated_at
          FROM jrc_backoffice_authority_proposals WHERE id=#{record.id}
        SQL
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey, /bo_authority_exact_version_origin/)
    expect(record.reload.account_id).to eq(account.id)
  end

  it 'preserves the pinned policy of an open case after a newer rule is published' do
    record = approval
    original = record.policy_version_id
    manager = JrcApprovals::Policies.new(account: account, user: actor)
    newer = approval_definition([reviewer], priority: 20)
    manager.edit!(policy_id: policy.id, expected_version: policy.reload.lock_version, name: 'TESTE SINTÉTICO — Nova regra', definition: newer)
    manager.validate!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    manager.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    expect(policy.reload.current_version_id).not_to eq(original)
    approval_vote(domain, reviewer, record)
    expect(record.reload.policy_version_id).to eq(original)
    expect(JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call[:status]).to eq('verified')
  end

  it 'requires all people from a joint roster in the same legal case' do
    document
    previous = roster
    extra = create(:contact, account: account, company_id: domain[:customer].id, email: 'joint.authority@example.test')
    JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor).save!(
      contact_id: extra.id, personal_tax_identifier: '12345678909', expected_revision: 0
    )
    joint = JrcBackoffice::SignerRosters.new(account: account, actor: actor, request_id: operation.id).create!(
      idempotency_key: SecureRandom.uuid, expected_revision: previous.revision,
      expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract),
      customer_mode: 'joint', issuer_mode: 'single', change_reason: 'TESTE SINTÉTICO — Representação conjunta.',
      signers: [{ contact_id: domain[:customer_person].id, party: 'customer' }, { contact_id: extra.id, party: 'customer' },
                { contact_id: domain[:issuer_person].id, party: 'issuer' }]
    )
    legal = domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(contract.id),
                                      change_reason: 'TESTE SINTÉTICO — Minuta conjunta.')
    proposed = authority_input(legal, joint, document)
    policy
    expect { service.create!(**proposed, proofs: proposed[:proofs].take(2)) }.to raise_error(ArgumentError, /todos/)
    record = service.create!(**proposed)
    native = JrcApprovals::Request.find_by!(account_id: account.id, resource_type: record.class.name, resource_id: record.id)
    expect(native.snapshot.fetch('values')).to include('signer_count' => 3, 'joint_signature' => true)
    approval_vote(domain, reviewer, native)
    expect(JrcBackoffice::AuthorityStatus.new(proposal: record, actor: actor).call[:status]).to eq('verified')
    expect(contract.reload.signature_status).to eq('not_started')
  end

  it 'blocks previously approved representation after its declared validity expires' do
    approval_vote(domain, reviewer, approval)
    travel_to(31.days.from_now) do
      state = JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call
      expect(state[:status]).to eq('blocked')
      expect(state[:facts]).to include(validity_current: false)
    end
  end
end
