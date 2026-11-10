require 'digest'

# An explicit review of the exact unsigned native draft. Advice does not edit
# clauses, confer legal powers or replace the company's signature gate.
class JrcApprovals::DraftReviewCatalog
  KEY = 'contracts.draft_review'.freeze
  def self.install!
    entries = JrcApprovals::Catalog.instance_variable_get(:@entries)
    return if entries[KEY]&.model.equal?(JrcCrm::Contract)
    JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize { entries.delete(KEY) }
    fields = JrcApprovals::CommercialCatalog::FIELDS.merge('draft_version' => 'integer', 'draft_digest' => 'string')
    JrcApprovals::Catalog.register(key: KEY, version: 1, model: JrcCrm::Contract, fields: fields,
      authorize: ->(actor, source) { readable?(source, actor) },
      request_authorize: ->(actor, source) { editable?(source, actor) },
      capture: ->(source, actor) { capture(source, actor) },
      verify: ->(source, actor) { verify(source, actor) })
  end

  def self.source(source, actor)
    access = JrcBackoffice::ContractAccess.new(account: source.account, actor: actor)
    version = JrcBackoffice::ContractVersion.where(account_id: source.account_id, contract_id: source.id).order(number: :desc).first!
    request = access.request(version.backoffice_request_id)
    raise ActiveRecord::RecordNotFound unless access.contract!(request).id == source.id
    [access, request, version]
  end

  def self.mutable?(contract)
    !%w[sent signed].include?(contract.signature_status) && !%w[active completed canceled terminated].include?(contract.status)
  end

  def self.readable?(contract, actor)
    source(contract, actor)
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end

  def self.editable?(contract, actor)
    access, request, = source(contract, actor)
    access.writable!(request)
    JrcBackoffice::Signatures::DeliveryGuard.check_editable!(contract)
    mutable?(contract)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError
    false
  end

  def self.capture(contract, actor)
    _access, request, version = source(contract, actor)
    digest = JrcBackoffice::ContractVersions.new(account: contract.account, actor: actor, request_id: request.id).source_digest(contract.id)
    raise JrcApprovals::Error, 'CONTEXT_STALE' unless digest == version.source_digest
    native = JrcApprovals::CommercialCatalog.capture(contract)
    native[:values] = native[:values].merge(draft_version: version.number, draft_digest: version.source_digest)
    native
  end

  def self.verify(contract, actor)
    return false unless editable?(contract, actor)
    _access, _request, version = source(contract, actor)
    digest = Digest::SHA256.hexdigest(version.pdf_blob.download)
    return false unless digest == version.pdf_sha256
    capture(contract.reload, actor)
    editable?(contract, actor)
  end
end
