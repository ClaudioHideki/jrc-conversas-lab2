# Adapter over existing modules. It never writes a decision or invokes providers.
class JrcBackoffice::NativeRequirements
  def initialize(request:, actor:, verify_bytes: false)
    @request, @actor, @verify_bytes = request, actor, verify_bytes
  end

  def facts
    { 'request_kind' => @request.request_kind, 'business_unit_id' => @request.business_unit_id,
      'product_id' => @request.sales_order.order_items.order(:product_id).distinct.pluck(:product_id).compact,
      'customer_kind' => JrcBackoffice::RequirementCatalog.customer_kind(@request),
      'request_id' => @request.id, 'order_id' => @request.sales_order_id,
      'contact_id' => @request.contact_id, 'customer_id' => @request.contact&.company_id,
      'order_contact_id' => @request.sales_order.contact_id }
  end

  def call(kind, definition)
    case kind
    when 'document' then document_state(definition.fetch('document_key'), human: definition['requires_human_review'] == true)
    when 'signature' then JrcBackoffice::SignatureRelease.satisfied?(@request) ? 'satisfied' : 'pending'
    when 'approval' then approval_state(definition.fetch('source'))
    when 'field' then present?(field(definition.fetch('field'))) ? 'satisfied' : 'missing'
    when 'validation' then registration_state(definition.fetch('source'))
    else 'unavailable'
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    'unavailable'
  rescue JrcBackoffice::DocumentSafety::NotClean, ActiveStorage::IntegrityError
    'quarantined'
  end

  private

  def document_state(key, human: false)
    version = @request.document_versions.where(account_id: @request.account_id, document_key: key).order(version: :desc).first
    return 'missing' unless version

    safety = JrcBackoffice::DocumentSafety.new(version)
    scan = safety.current
    return 'quarantined' if scan && %w[infected checksum_mismatch].include?(scan.state)
    return 'pending' unless scan&.clean?

    safety.bytes! if @verify_bytes
    return 'pending' if human && !version.current_decision
    case version.status
    when 'approved' then 'satisfied'
    when 'rejected' then 'rejected'
    when 'expired' then 'expired'
    else 'pending'
    end
  end

  def approval_state(key)
    return 'unavailable' unless JrcApprovals::CommercialGate.mode(@request.account, key) == 'enforcement'

    source = { 'crm.order_price' => @request.sales_order, 'crm.order_terms' => @request.sales_order, 'backoffice.release' => @request,
               'contracts.company_signature' => @request.contract, 'contracts.draft_review' => @request.contract }.fetch(key)
    return 'missing' unless source

    result = JrcApprovals::CommercialGate.new(account: @request.account, user: @actor)
                                        .evaluate(key: key, resource_id: source.id)
    result[:status] == 'ready' ? 'satisfied' : 'pending'
  end

  def field(key)
    case key
    when 'customer.name' then @request.contact&.company&.name
    when 'customer.tax_id' then @request.contact&.company&.tax_id
    when 'contact.name' then @request.contact&.name
    when 'contact.email' then @request.contact&.email
    when 'contact.phone_number' then @request.contact&.phone_number
    when 'order.payment_condition' then @request.sales_order.payment_condition
    end
  end

  def registration_state(source)
    return signatory_powers_state if source == 'signatory_powers'
    evidence = JrcCrm::BackofficeDocumentChecklist.new(request: @request, actor: @actor).native_requirement_evidence(source)
    evidence ? 'satisfied' : 'missing'
  end

  def signatory_powers_state
    return 'missing' unless @request.contract_id
    version = JrcBackoffice::ContractVersion.where(account_id: @request.account_id, backoffice_request_id: @request.id,
      contract_id: @request.contract_id).order(number: :desc).first
    return 'missing' unless version
    proposal = JrcBackoffice::AuthorityProposal.where(account_id: @request.account_id, backoffice_request_id: @request.id,
      contract_version_id: version.id).order(revision: :desc).first
    return 'pending' unless proposal
    value = JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: @actor).call(verify: @verify_bytes)
    value[:status] == 'verified' ? 'satisfied' : 'pending'
  end

  def present?(value)
    value.present?
  end
end
