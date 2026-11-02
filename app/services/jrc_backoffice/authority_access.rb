# A reviewer receives only the exact sealed legal context assigned by the
# native Central. This grants no generic Backoffice ownership/write access,
# directory browsing, identifier editing or provider action.
class JrcBackoffice::AuthorityAccess
  attr_reader :account, :actor

  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @backoffice = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @central = JrcApprovals::Authorization.new(account: account, user: actor)
  end

  def authoring_version!(request_id, version_id)
    request = @backoffice.writable!(@backoffice.request(request_id))
    contract = @backoffice.contract!(request)
    JrcBackoffice::Signatures::DeliveryGuard.check_editable!(contract)
    if contract.signature_status.in?(%w[sent signed])
      raise ArgumentError, 'Preserve o contrato enviado ou assinado; use o fluxo autorizado de revisão.'
    end

    version = JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: request.id).scope.find(version_id)
    unless version.contract_id == contract.id && version.source_format_version == 2 && version.signer_roster_id
      raise ArgumentError, 'Gere a versão contratual com os assinantes antes de validar poderes.'
    end

    authorize_creation!(version)
    version
  end

  def authorize_creation!(version)
    authorize_scope!(version.signer_roster)
    @central.authorize!('request_create', company_id: version.signer_roster.snapshot.fetch('issuer').fetch('id'),
                                          unit_id: version.signer_roster.snapshot.fetch('business_unit_id'))
  end

  def read_case!(record)
    @backoffice.membership!
    raise ActiveRecord::RecordNotFound unless record.account_id == account.id

    authorize_scope!(record.signer_roster)
    return record if backoffice_reader?(record)

    readable = approval_requests(record).any? do |request|
      JrcApprovals::RequestVisibility.authorize!(account: account, user: actor, record: request)
      true
    rescue Pundit::NotAuthorizedError
      false
    end
    raise Pundit::NotAuthorizedError unless readable

    record
  end

  def approval_requests(record)
    JrcApprovals::Request.where(account_id: account.id, resource_type: record.class.name, resource_id: record.id,
                                module_key: 'contracts', event_key: 'signer_authority')
  end

  private

  def authorize_scope!(roster)
    source = roster.snapshot
    company_id = source.fetch('issuer').fetch('id')
    unit_id = source.fetch('business_unit_id')
    JrcApprovals::Authorization.scope!(account, company_id, unit_id)
    raise Pundit::NotAuthorizedError unless @central.covered?(company_id, unit_id)
  end

  def backoffice_reader?(record)
    @backoffice.request(record.backoffice_request_id)
    @backoffice.contracts.exists?(id: record.contract_id)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  end
end
