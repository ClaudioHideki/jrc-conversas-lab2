require 'rails_helper'
require Rails.root.join('db/migrate/20261102090100_create_backoffice_signature_deliveries')

RSpec.describe JrcBackoffice::Signatures::Admissions, :approval_core, :authority_core do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:reviewer) { approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide]) }
  let(:document) { authority_document(domain) }
  let(:roster) { authority_roster(domain) }
  let(:version) do
    document
    roster
    domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(domain[:contract].id),
                              change_reason: 'TESTE SINTÉTICO — Versão para intenção durável.')
  end
  let(:proposal) do
    authority_policy(domain, [reviewer])
    JrcBackoffice::AuthorityProposals.new(account: account, actor: actor, request_id: domain[:operation].id)
                                     .create!(**authority_input(version, roster, document))
  end
  let(:approval) { JrcApprovals::Request.find_by!(account_id: account.id, resource_type: proposal.class.name, resource_id: proposal.id) }
  let(:provider) do
    user = create(:user, account: account, role: :administrator)
    account.jrc_crm_user_business_units.create!(user: user, scope: 'GROUP', active: true, structure_managed: true)
    configuration = JrcBackoffice::SignatureConfiguration.new(account: account, actor: user)
    attributes = { environment: 'demo', enabled: true, integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
                   external_account_id: SecureRandom.uuid, private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
                   connect_hmac_keys: ['synthetic-delivery-hmac-no-external-validation-12345678'] }
    connection = configuration.save!(attributes: attributes, expected_revision: 0).connection
    # Fixture verification only; external consent and Connect remain untested.
    connection.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    { configuration: configuration, attributes: attributes, connection: connection }
  end
  let(:service) { described_class.new(account: account, actor: actor, request_id: domain[:operation].id) }
  let(:input) do
    { version_id: version.id, authority_proposal_id: proposal.id, expected_connection_id: provider.fetch(:connection).id,
      expected_source_digest: version.source_digest, idempotency_key: SecureRandom.uuid }
  end
  let(:delivery) do
    approval_vote(domain, reviewer, approval)
    service.create!(**input)
  end

  before do
    raise 'Owned candidate database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    domain
  end

  it 'commits an encrypted immutable intent with exact legal/provider facts without sending or signing' do
    expect(JrcBackoffice::Signatures::Gateway).not_to receive(:new)
    record = delivery
    source = record.snapshot
    expect(record.state).to eq('prepared')
    expect(record.external_id).to be_nil
    expect(source).to include('contract_version_id' => version.id, 'pdf_sha256' => version.pdf_sha256,
                              'authority_proposal_id' => proposal.id, 'connection_id' => provider.fetch(:connection).id,
                              'provider' => 'docusign', 'environment' => 'demo',
                              'external_account_id' => provider.fetch(:attributes)[:external_account_id])
    expect(source['authority_approvals'].first).to include('id' => approval.id, 'cycle' => approval.cycle,
                                                           'policy_version_id' => approval.policy_version_id)
    expect(source['recipients'].length).to eq(2)
    expect(source['recipients'].all? { |row| row['required'] && row['anchor'].present? }).to be(true)
  end

  it 'protects private admission data in storage and DTOs without releasing the unsigned operation' do
    record = delivery
    source = record.snapshot
    expect(source.to_s).not_to include('personal_tax_identifier', 'private_key', 'connect_hmac_keys')
    sql = "SELECT source_snapshot FROM jrc_backoffice_signature_deliveries WHERE id=#{record.id}"
    expect(ActiveRecord::Base.connection.select_value(sql)).not_to include('customer.authority@example.test',
                                                                           provider.fetch(:attributes)[:external_account_id])
    expect(record.serializable_hash.to_s).not_to include('source_snapshot', 'recipients', 'transaction_id',
                                                         provider.fetch(:attributes)[:external_account_id])
    expect(domain[:contract].reload.signature_status).to eq('not_started')
    expect(JrcBackoffice::SignatureRelease.satisfied?(domain[:operation])).to be(false)
    expect(account.jrc_crm_audit_events.where(event_type: 'signature_delivery_admitted').count).to eq(1)
  end

  it 'rejects a merely pending legal case and leaves no partial ledger' do
    expect(approval.state).to eq('pending')
    expect { service.create!(**input) }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'AUTHORITY_APPROVAL_REQUIRED')
    expect(service.scope).to be_empty
    expect(JrcBackoffice::SignatureDeliveryEvent.where(account_id: account.id)).to be_empty
  end

  it 'replays an identical actor intent and rejects changed input or a competing intent' do
    record = delivery
    expect(service.create!(**input).id).to eq(record.id)
    expect { service.create!(**input, expected_connection_id: 0) }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_INTENT_CHANGED')
    expect do
      service.create!(**input, idempotency_key: SecureRandom.uuid)
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_IN_PROGRESS')
    expect(record.events.count).to eq(1)
  end

  it 'pins only the legal cases required by this proposal rather than unrelated generic requests' do
    approval_vote(domain, reviewer, approval)
    extra = JrcApprovals::Requests.new(account: account, user: actor).create!(
      key: JrcBackoffice::AuthorityCatalog::KEY, resource_id: proposal.id, idempotency_key: SecureRandom.uuid
    ).first
    expect(extra.state).to eq('pending')
    record = service.create!(**input)
    expect(record.snapshot.fetch('authority_approvals').pluck('id')).to eq([approval.id])
    expect(record.state).to eq('prepared')
  end

  it 'pins the original connection/environment/account when the default changes for future sends' do
    record = delivery
    original = record.snapshot
    provider.fetch(:configuration).save!(
      attributes: provider.fetch(:attributes).merge(environment: 'production', external_account_id: SecureRandom.uuid), expected_revision: 1
    )
    expect(record.reload.snapshot).to eq(original)
    expect(record.connection_id).to eq(provider.fetch(:connection).id)
    expect(record.connection.environment).to eq('demo')
    expect(service.create!(**input).id).to eq(record.id)
    expect(record.state).to eq('prepared')
  end

  it 'does not reuse an actor idempotency key across two authorized operational requests' do
    record = delivery
    other = account.jrc_crm_backoffice_requests.create!(
      sales_order: domain[:order], contract: domain[:contract], owner: actor, requested_by: actor,
      contact: domain[:customer_person], business_unit: domain[:unit], request_kind: 'change', stage: 'contract',
      title: 'TESTE SINTÉTICO — Outra operação autorizada'
    )
    other_service = described_class.new(account: account, actor: actor, request_id: other.id)
    expect { other_service.create!(**input) }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_INTENT_CHANGED')
    expect(record.reload.events.count).to eq(1)
    expect(JrcBackoffice::SignatureDelivery.where(account_id: account.id).count).to eq(1)
  end

  it 'keeps an uncertain dispatch reserved and prevents a second dispatch claim at the database boundary' do
    record = delivery
    record.events.create!(account: account, connection: record.connection, kind: 'dispatch_started', event_key: 'claim', source_snapshot: '{}')
    record.events.create!(account: account, connection: record.connection, kind: 'send_uncertain', event_key: 'outcome', source_snapshot: '{}')
    expect(record.state).to eq('uncertain')
    expect { service.cancel_prepared!(record.id) }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_ALREADY_DISPATCHED')
    expect do
      JrcBackoffice::SignatureDeliveryEvent.transaction(requires_new: true) do
        record.events.create!(account: account, connection: record.connection, kind: 'dispatch_started',
                              event_key: 'other-claim', source_snapshot: '{}')
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(JrcBackoffice::Signatures::DeliveryGuard.active(domain[:contract]).pluck(:id)).to eq([record.id])
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'stores an opaque provider reference without imposing DocuSign identifiers on the internal ledger' do
    record = delivery
    reference = 'external-contract/reference-2026:42'
    record.events.create!(account: account, connection: record.connection, kind: 'send_confirmed', event_key: 'opaque-ack',
                          external_id: reference, source_snapshot: '{}')
    expect(record.reload.external_id).to eq(reference)
    expect(record.state).to eq('sent')
    expect(domain[:contract].reload.signature_status).to eq('not_started')
  end

  it 'rejects a changed default preview rather than silently selecting another verified connection' do
    approval_vote(domain, reviewer, approval)
    input
    replacement = provider.fetch(:configuration).save!(attributes: provider.fetch(:attributes), expected_revision: 1).connection
    replacement.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    expect { service.create!(**input) }.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'CONNECTION_CHANGED')
    expect(service.scope).to be_empty
  end

  it 'verifies the sealed document bytes again before durable admission' do
    approval_vote(domain, reviewer, approval)
    input
    original = document.file.blob.download
    document.file.blob.service.upload(document.file.blob.key, StringIO.new('%PDF-corrupt-synthetic'), checksum: nil)
    expect { service.create!(**input) }.to raise_error(JrcApprovals::Error, 'AUTHORITY_EVIDENCE_UNAVAILABLE')
    expect(service.scope).to be_empty
  ensure
    document.file.blob.service.upload(document.file.blob.key, StringIO.new(original), checksum: nil) if original
  end

  it 'denies another account, an unassigned reviewer and revoked sender coverage including retries' do
    record = delivery
    expect do
      described_class.new(account: account, actor: reviewer.user, request_id: domain[:operation].id).create!(**input)
    end.to raise_error(ActiveRecord::RecordNotFound)
    foreign = create(:user, account: create(:account), role: :administrator)
    expect do
      described_class.new(account: account, actor: foreign, request_id: domain[:operation].id).cancel_prepared!(record.id)
    end.to raise_error(Pundit::NotAuthorizedError)
    account.jrc_crm_user_business_units.where(user: actor).each { |row| row.update!(active: false) }
    expect { service.create!(**input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(record.reload.events.count).to eq(1)
  end

  it 'blocks legal writers/direct SQL during the active intent while preserving operational updates' do
    record = delivery
    expect do
      domain[:versions].create!(idempotency_key: SecureRandom.uuid, expected_source_digest: version.source_digest, change_reason: 'Outra versão')
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_IN_PROGRESS')
    expect do
      JrcBackoffice::AuthorityAccess.new(account: account, actor: actor).authoring_version!(domain[:operation].id, version.id)
    end.to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_IN_PROGRESS')
    expect do
      JrcCrm::Contract.transaction(requires_new: true) do
        ActiveRecord::Base.connection.execute("UPDATE jrc_crm_contracts SET content_override='Rewrite during send' WHERE id=#{domain[:contract].id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /signature_delivery_source_locked/)
    domain[:contract].reload.update!(updated_at: Time.current)
    expect(domain[:contract].content_override).to eq(version.snapshot.dig('contract', 'content_override'))
    expect(record.reload.state).to eq('prepared')
    context = JrcBackoffice::AuthorityOverview.new(account: account, actor: actor, request_id: domain[:operation].id).call
    expect(context[:can_propose]).to be(false)
    expect(context[:current][:status][:status]).to eq('verified')
  end

  it 'cancels only an unsent intent idempotently and requires a new version for a new envelope' do
    record = delivery
    expect(service.cancel_prepared!(record.id).state).to eq('canceled')
    expect(service.cancel_prepared!(record.id).state).to eq('canceled')
    expect(record.events.where(kind: 'canceled_before_send').count).to eq(1)
    expect(JrcBackoffice::Signatures::DeliveryGuard.active(domain[:contract])).to be_empty
    expect { service.create!(**input, idempotency_key: SecureRandom.uuid) }
      .to raise_error(JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_VERSION_ALREADY_REGISTERED')
    domain[:contract].update!(content_override: 'TESTE SINTÉTICO — Revisão posterior ao cancelamento.')
    expect(record.reload.snapshot['pdf_sha256']).to eq(version.pdf_sha256)
  end

  it 'preserves immutable rows/events against SQL mutation and refuses destructive rollback' do
    record = delivery
    expect { record.update!(connection: provider.fetch(:connection)) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { record.events.first.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      JrcBackoffice::SignatureDelivery.transaction(requires_new: true) do
        sql = "UPDATE jrc_backoffice_signature_deliveries SET transaction_id='#{SecureRandom.uuid}' WHERE id=#{record.id}"
        ActiveRecord::Base.connection.execute(sql)
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    expect { CreateBackofficeSignatureDeliveries.new.migrate(:down) }.to raise_error(ActiveRecord::IrreversibleMigration, /Preserve admitted sends/)
    expect(record.reload.snapshot['authority_digest']).to eq(proposal.source_digest)
  end

  it 'enforces the exact tenant/connection of events even when model validation is bypassed' do
    record = delivery
    stranger = create(:account)
    expect do
      JrcBackoffice::SignatureDeliveryEvent.transaction(requires_new: true) do
        sql = 'INSERT INTO jrc_backoffice_signature_delivery_events ' \
              '(account_id,delivery_id,connection_id,kind,event_key,source_snapshot,created_at,updated_at) VALUES ' \
              "(#{stranger.id},#{record.id},#{provider.fetch(:connection).id},'send_uncertain','forged','{}',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)"
        ActiveRecord::Base.connection.execute(sql)
      end
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(record.events.count).to eq(1)
  end
end
