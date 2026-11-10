# Shared synthetic setup for real commit/concurrency tests. Domain decisions
# use native services. Only scanner verification and provider HTTP are mocked.
module JrcSignatureDeliveryHelpers
  def admitted_signature_domain
    account = create(:account)
    actor = create(:user, account: account, role: :administrator)
    domain = authority_domain(account, actor)
    legal = signature_legal_context(domain)
    connection = synthetic_delivery_connection(account)
    delivery = JrcBackoffice::Signatures::Admissions.new(account: account, actor: actor, request_id: domain[:operation].id).create!(
      version_id: legal[:version].id, authority_proposal_id: legal[:proposal].id, expected_connection_id: connection.id,
      expected_source_digest: legal[:version].source_digest, idempotency_key: SecureRandom.uuid
    )
    domain.merge(legal).merge(delivery: delivery, connection: connection)
  end

  def signature_legal_context(domain)
    document = authority_document(domain)
    roster = authority_roster(domain)
    version = domain[:versions].create!(
      idempotency_key: SecureRandom.uuid, expected_source_digest: domain[:versions].source_digest(domain[:contract].id),
      change_reason: 'TESTE SINTÉTICO — Envio durável.'
    )
    proposal = signature_approved_proposal(domain, version, roster, document)
    { version: version, proposal: proposal, document: document }
  end

  def signature_approved_proposal(domain, version, roster, document)
    reviewer = approval_actor(domain, permissions: %w[jrc_crm jrc_approvals_decide])
    authority_policy(domain, [reviewer])
    proposal = JrcBackoffice::AuthorityProposals.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id)
                                                .create!(**authority_input(version, roster, document))
    approval = JrcApprovals::Request.find_by!(account_id: domain[:account].id, resource_type: proposal.class.name, resource_id: proposal.id)
    approval_vote(domain, reviewer, approval)
    proposal
  end

  def synthetic_delivery_connection(account)
    administrator = create(:user, account: account, role: :administrator)
    account.jrc_crm_user_business_units.create!(user: administrator, scope: 'GROUP', active: true, structure_managed: true)
    configuration = JrcBackoffice::SignatureConfiguration.new(account: account, actor: administrator)
    revision = JrcBackoffice::SignatureIntegration.find_by(account_id: account.id)&.revision || 0
    record = configuration.save!(expected_revision: revision, attributes: {
                                   environment: 'demo', enabled: true, integration_key: SecureRandom.uuid, impersonated_user_id: SecureRandom.uuid,
                                   external_account_id: SecureRandom.uuid, private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
                                   connect_hmac_keys: ['synthetic-durable-delivery-test-hmac-only-1234567890']
                                 }).connection
    record.update!(authorization_checked_at: Time.current, connect_checked_at: Time.current)
    record
  end

  def signature_receipt(connection:, event:, external_id:, at: Time.current)
    body = { event: event, generatedDateTime: at.iso8601(6),
             data: { accountId: connection.external_account_id, envelopeId: external_id } }.to_json
    key = connection.credentials.fetch('connect_hmac_keys').first
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', key, body))
    JrcBackoffice::Docusign::ConnectInbox.receive!(public_id: connection.public_id, raw_body: body, signatures: [signature])
  end
end

RSpec.configure { |config| config.include JrcSignatureDeliveryHelpers, :signature_delivery_core }
