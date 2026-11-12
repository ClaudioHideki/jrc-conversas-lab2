# Synthetic domain setup shared by service/API integration tests. Every
# business action uses the native services. Only the AV response is simulated.
module JrcBackofficeAuthorityHelpers
  def authority_domain(account, actor)
    account.enable_features!('jrc_crm', 'jrc_customer_master', 'jrc_approvals')
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Emitente', relationship_type: 'internal', tax_id: '11444777000161')
    customer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente', relationship_type: 'customer', tax_id: '11222333000181')
    unit = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade', code: SecureRandom.hex(6), company_id: issuer.id)
    customer_person = create(:contact, account: account, company_id: customer.id, email: 'customer.authority@example.test')
    issuer_person = create(:contact, account: account, company_id: issuer.id, email: 'issuer.authority@example.test')
    domain = { account: account, actor: actor, company: issuer, customer: customer, unit: unit,
               customer_person: customer_person, issuer_person: issuer_person }
    authority_identity_setup(domain)
    domain.merge(authority_operation(domain))
  end

  def authority_identity_setup(domain)
    domain[:account].jrc_crm_user_business_units.create!(user: domain[:actor], scope: 'BUSINESS_UNIT', company: domain[:company],
                                                         business_unit: domain[:unit], structure_managed: true, active: true)
    writer = JrcCustomers::SigningIdentityWriter.new(account: domain[:account], actor: domain[:actor])
    writer.save!(contact_id: domain[:customer_person].id, personal_tax_identifier: '11144477735', expected_revision: 0)
    writer.save!(contact_id: domain[:issuer_person].id, personal_tax_identifier: '52998224725', expected_revision: 0)
  end

  def authority_operation(domain)
    account, actor = domain.values_at(:account, :actor)
    order = account.jrc_crm_sales_orders.create!(owner: actor, contact: domain[:customer_person], business_unit: domain[:unit], status: 'approved')
    contract = account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: domain[:customer_person], business_unit: domain[:unit],
                                                 content_override: 'TESTE SINTÉTICO — Representação exige decisão humana; nenhum envio externo.')
    operation = account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                            contact: domain[:customer_person], business_unit: domain[:unit], stage: 'contract',
                                                            title: 'TESTE SINTÉTICO — Poderes',
                                                            metadata: { required_documents: ['representation'] })
    { order: order, contract: contract, operation: operation, documents: JrcBackoffice::Documents.new(request: operation, actor: actor),
      versions: JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: operation.id),
      file: Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf') }
  end

  def authority_document(domain)
    record = domain[:documents].upload!(key: 'representation', file: domain[:file], idempotency_key: SecureRandom.uuid)
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(record.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => record.sha256
    )
    JrcBackoffice::DocumentSafety.new(record).scan!
    record.create_analysis!(analyzer_version: 'synthetic-authority-fixture/1', state: 'review_required', evidence: {})
    domain[:documents].decide!(version: record, status: 'approved', reason: 'TESTE SINTÉTICO — Evidência conferida para revisão jurídica.')
    record
  end

  def authority_roster(domain)
    JrcBackoffice::SignerRosters.new(account: domain[:account], actor: domain[:actor], request_id: domain[:operation].id).create!(
      idempotency_key: SecureRandom.uuid, expected_revision: 0, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(domain[:contract]),
      customer_mode: 'single', issuer_mode: 'single', change_reason: 'TESTE SINTÉTICO — Pessoas canônicas.',
      signers: [{ contact_id: domain[:customer_person].id, party: 'customer' }, { contact_id: domain[:issuer_person].id, party: 'issuer' }]
    )
  end

  def authority_policy(domain, reviewers, **definition_options)
    manager = JrcApprovals::Policies.new(account: domain[:account], user: domain[:actor])
    record = manager.create!(code: SecureRandom.hex(6), name: 'TESTE SINTÉTICO — Representação', module_key: 'contracts',
                             event_key: 'signer_authority', issuer_company_id: domain[:company].id, business_unit_id: domain[:unit].id,
                             definition: approval_definition(reviewers, **definition_options))
    manager.validate!(policy_id: record.id, expected_version: record.lock_version)
    manager.publish!(policy_id: record.id, expected_version: record.reload.lock_version)
    record.reload
  end

  def authority_input(version, roster, document)
    { version_id: version.id, expected_revision: 0, expected_source_digest: version.source_digest, idempotency_key: SecureRandom.uuid,
      change_reason: 'TESTE SINTÉTICO — Submeter comprovação de poderes.',
      proofs: roster.snapshot.fetch('signers').map do |person|
        { 'signer_key' => person.fetch('key'), 'basis' => 'legal_representative', 'reason' => 'TESTE SINTÉTICO — Documento e ato vigentes.',
          'document_version_ids' => [document.id], 'valid_from' => Date.current.iso8601,
          'valid_until' => (Date.current + 30).iso8601, 'no_expiry' => false }
      end }
  end
end

RSpec.configure { |config| config.include JrcBackofficeAuthorityHelpers, :authority_core }
