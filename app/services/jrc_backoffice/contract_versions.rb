require 'digest'
require 'stringio'

class JrcBackoffice::ContractVersions
  class Changed < StandardError; end

  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
  end

  def scope
    request = @access.request(@request_id)
    JrcBackoffice::ContractVersion.where(account_id: @access.account.id, backoffice_request_id: request.id,
                                         contract_id: @access.contracts.select(:id))
  end

  def source_digest(contract_id)
    request = @access.request(@request_id)
    contract = @access.contract!(request)
    raise Changed unless contract.id == contract_id

    JrcBackoffice::ContractSnapshot.digest(contract, signer_roster: roster_for(request, contract))
  end

  def create!(idempotency_key:, expected_source_digest:, change_reason:)
    @pending_blob = nil
    JrcApprovals::Ledger.key!(idempotency_key)
    raise ArgumentError, 'Informe o motivo da revisão.' unless change_reason.is_a?(String) && change_reason.strip.length.between?(1, 2000)

    input = { idempotency_key: idempotency_key, source_digest: expected_source_digest, change_reason: change_reason.strip }
    # Serialize source/config writers without blocking the KEY SHARE locks
    # needed by native document/attachment/audit inserts on ancestor FKs.
    @access.account.with_lock('FOR NO KEY UPDATE', requires_new: true) do
      request = @access.writable!(@access.request(@request_id))
      request.sales_order.with_lock('FOR NO KEY UPDATE') do
        request.with_lock('FOR NO KEY UPDATE') do
          contract = @access.contract!(request)
          contract.with_lock('FOR NO KEY UPDATE') { generate!(request, contract, input) }
        end
      end
    end
  rescue StandardError
    clean_uncommitted_blob
    raise
  ensure
    @pending_blob = nil
  end

  def download!(id)
    version = scope.find(id)
    bytes = version.pdf_blob.download
    raise ActiveStorage::IntegrityError unless Digest::SHA256.hexdigest(bytes) == version.pdf_sha256

    scope.find(version.id) # Revalidate both request and historical contract after storage I/O.
    audit!(version, 'backoffice_contract_version_accessed')
    [version, bytes]
  end

  def differences(id)
    version = scope.find(id)
    previous = JrcBackoffice::ContractVersion.where(account_id: version.account_id, contract_id: version.contract_id)
                                             .where('number < ?', version.number).order(number: :desc).first
    previous = nil unless previous && previous_visible?(previous)
    before = previous&.snapshot || {}
    current = version.snapshot
    scope.find(version.id)
    before = {} if previous && !previous_visible?(previous)
    JrcBackoffice::ContractSnapshot.differences(JrcBackoffice::ContractSnapshot.presentation(before),
                                                JrcBackoffice::ContractSnapshot.presentation(current))
  end

  private

  def previous_visible?(version)
    @access.request(version.backoffice_request_id)
    @access.contracts.exists?(id: version.contract_id)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def generate!(request, contract, input)
    previous = existing_version!(contract, input)
    return previous if previous

    check_generation!(request, contract)
    roster = roster_for(request, contract)
    validate_roster!(request, contract, roster)
    snapshot = JrcBackoffice::ContractSnapshot.capture(contract.reload, signer_roster: roster)
    digest = JrcBackoffice::ContractSnapshot.digest_data(snapshot)
    raise Changed unless input[:source_digest] == digest

    number = JrcBackoffice::ContractVersion.where(account_id: contract.account_id, contract_id: contract.id).maximum(:number).to_i + 1
    bytes = render_version(contract, number, roster)
    raise Changed unless JrcBackoffice::ContractSnapshot.digest(contract.reload, signer_roster: roster) == digest

    validate_roster!(request, contract, roster)
    @access.writable!(request)
    input[:signer_roster] = roster
    persist!(build_version(request, contract, number, snapshot, input), bytes)
  end

  def render_version(contract, number, roster)
    options = { revision: number }
    options[:signers] = roster.snapshot.fetch('signers') if roster
    JrcCrm::ContractPdfService.new(contract, **options).call
  end

  def roster_for(request, contract)
    JrcBackoffice::SignerRoster.where(account_id: @access.account.id, backoffice_request_id: request.id, contract_id: contract.id)
                               .order(revision: :desc).first
  end

  def validate_roster!(request, contract, roster)
    return unless roster

    source = JrcBackoffice::SignerRosterSource.new(account: @access.account, actor: @access.actor, request: request, contract: contract)
    source.assert_current!(roster)
  end

  def existing_version!(contract, input)
    record = JrcBackoffice::ContractVersion.find_by(account_id: contract.account_id, contract_id: contract.id,
                                                    idempotency_key: input[:idempotency_key])
    return unless record

    raise Changed unless record.source_digest == input[:source_digest] && record.change_reason == input[:change_reason]

    record
  end

  def check_generation!(request, contract)
    JrcBackoffice::Signatures::DeliveryGuard.check_editable!(contract)
    if contract.signature_status.in?(%w[sent signed])
      raise ArgumentError, 'Preserve o contrato enviado ou assinado; use o fluxo de revisão autorizado.'
    end

    JrcBackoffice::ContractRelease.check!(order: request.sales_order, actor: @access.actor)
    JrcCrm::BackofficeDocumentChecklist.new(request: request, actor: @access.actor).sync!
    raise ArgumentError, 'Conclua a documentação obrigatória antes de gerar a versão contratual.' unless documents_ready?(request)

    return unless contract.contract_template.nil? && contract.content_override.blank?

    raise ArgumentError, 'Selecione um modelo ou informe a minuta contratual.'
  end

  def build_version(request, contract, number, snapshot, input)
    older = JrcBackoffice::ContractVersion.where(account_id: contract.account_id, contract_id: contract.id).order(number: :desc).first
    paths = JrcBackoffice::ContractSnapshot.differences(older&.snapshot || {}, snapshot).pluck(:path)
    JrcBackoffice::ContractVersion.new(account: @access.account, backoffice_request: request, contract: contract,
                                       created_by: @access.actor, number: number, idempotency_key: input[:idempotency_key],
                                       source_digest: input[:source_digest], source_snapshot: JrcServiceDesk::CanonicalJson.dump(snapshot),
                                       change_reason: input[:change_reason], change_paths: paths, signer_roster: input[:signer_roster],
                                       source_format_version: input[:signer_roster] ? 2 : 1)
  end

  def persist!(record, bytes)
    valid = bytes.is_a?(String) && bytes.start_with?('%PDF-') && bytes.bytesize <= 20.megabytes
    raise ArgumentError, 'O gerador não retornou um PDF válido.' unless valid

    filename = "#{record.contract.contract_number}-v#{record.number}.pdf"
    record.pdf_blob = JrcBackoffice::PrivateBlob.upload_owned(io: StringIO.new(bytes), filename: filename, content_type: 'application/pdf',
                                                              marker: 'jrc_contract_generated')
    @pending_blob = record.pdf_blob
    @access.writable!(record.backoffice_request)
    record.pdf_sha256 = Digest::SHA256.hexdigest(bytes)
    record.save!
    audit!(record, 'backoffice_contract_version_created')
    record
  end

  def documents_ready?(request)
    request.precontract_documents.all? { |key| document_ready?(request, key) }
  end

  def document_ready?(request, key)
    row = Array(request.metadata['document_checklist']).find { |entry| entry['key'] == key }
    return row['status'] == 'approved' if row && row['source'] != 'manual'

    version = request.document_versions.where(document_key: key).order(version: :desc).first
    return manual_document_ready?(request, version) if version

    request.workflow_version == 1 && request.metadata.dig('document_statuses', key) == 'approved'
  end

  def manual_document_ready?(request, version)
    return false unless version.decisions.order(id: :desc).first&.status == 'approved'
    return true if request.workflow_version == 1

    JrcBackoffice::DocumentSafety.new(version).current&.clean?
  end

  def clean_uncommitted_blob
    JrcBackoffice::ContractVersion.clean_uncommitted_pdf(@pending_blob)
  end

  def audit!(version, event)
    JrcCrm::AuditEvent.create!(account: @access.account, actor_type: 'User', actor_id: @access.actor.id, event_type: event,
                               resource_type: version.class.name, resource_id: version.id,
                               metadata: { source: 'backoffice_contracts', backoffice_request_id: @request_id,
                                           number: version.number, pdf_sha256: version.pdf_sha256 })
  end
end
