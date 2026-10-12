# Native CRM adapters. Installation registers contracts, never policies or tenant activation.
class JrcApprovals::CommercialCatalog
  EVENTS = {
    'crm.deal_price' => 'JrcCrm::Deal',
    'crm.proposal_send' => 'JrcCrm::Proposal',
    'crm.proposal_convert' => 'JrcCrm::Proposal',
    'crm.order_price' => 'JrcCrm::SalesOrder',
    'backoffice.release' => 'JrcCrm::BackofficeRequest',
    'contracts.company_signature' => 'JrcCrm::Contract'
  }.freeze
  PRICE_FAMILY = 'crm.price_exception'.freeze
  PRICE_EVENTS = %w[deal_price proposal_send proposal_convert order_price].freeze
  FIELDS = { 'price_status' => 'string', 'below_minimum_count' => 'integer',
             'context_digest' => 'string', 'signature_evidence' => 'string',
             'total_cents' => 'integer', 'currency' => 'string', 'item_count' => 'integer',
             'order_origin' => 'string', 'customer_relationship' => 'string' }.freeze

  def self.install!
    EVENTS.each do |key, model_name|
      # Only this fixed server catalog resolves model names; no client constantization.
      model = model_name.constantize
      existing = JrcApprovals::Catalog.instance_variable_get(:@entries)[key]
      next if existing && existing.model.equal?(model)

      JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize do
        JrcApprovals::Catalog.instance_variable_get(:@entries).delete(key)
      end
      JrcApprovals::Catalog.register(key: key, version: 1, model: model, fields: FIELDS,
        authorize: ->(user, resource) { authorized?(user, resource) },
        capture: ->(resource) { capture(resource) })
    end
    unless JrcApprovals::Catalog.instance_variable_get(:@entries).key?(PRICE_FAMILY)
      JrcApprovals::Catalog.register(key: PRICE_FAMILY, version: 1, model: nil, policy_only: true, fields: FIELDS,
        authorize: ->(*) { false }, capture: ->(*) { raise JrcApprovals::Error, 'POLICY_TEMPLATE_ONLY' })
    end
  end

  def self.selection_events(module_key, event_key)
    return [event_key] unless module_key == 'crm'
    return PRICE_EVENTS + ['price_exception'] if event_key == 'price_exception'
    return [event_key, 'price_exception'] if PRICE_EVENTS.include?(event_key)

    [event_key]
  end

  def self.authorized?(user, resource)
    account = resource.account
    member = account.account_users.find_by(user_id: user&.id)
    return false unless account.active? && account.feature_enabled?('jrc_crm') && member &&
      member.user.active_for_authentication? && member.permissions.include?('jrc_crm')

    relation = resource.class.where(account_id: account.id, id: resource.id)
    relation = relation.where(owner_id: user.id) unless member.administrator?
    visible = JrcCrm::OrganizationalVisibility.new(account: account, user: user, relation: relation, include_company: false).call
    unit = business_unit(resource)
    return false unless unit && JrcApprovals::Authorization.new(account: account, user: user).covered?(unit.company_id, unit.id)
    return true if visible.exists?
    order_id = resource.is_a?(JrcCrm::SalesOrder) ? resource.id :
      (resource.is_a?(JrcCrm::Contract) ? resource.sales_order_id : nil)
    if order_id && JrcCrm::BackofficeRequest.where(account_id: account.id, sales_order_id: order_id, owner_id: user.id).exists?
      return true
    end

    # A designated reviewer can capture only this adapter's bounded technical context.
    # The native CRM record remains subject to its original owner/admin visibility.
    JrcApprovals::Request.where(account_id: account.id, resource_type: resource.class.name, resource_id: resource.id).any? do |request|
      begin
        JrcApprovals::RequestVisibility.authorize!(account: account, user: user, record: request)
        true
      rescue Pundit::NotAuthorizedError
        false
      end
    end
  end

  def self.commercial_resource(resource)
    resource.respond_to?(:sales_order) && !resource.is_a?(JrcCrm::Proposal) ? resource.sales_order : resource
  end

  def self.business_unit(resource)
    return resource.business_unit unless resource.is_a?(JrcCrm::Deal)

    # The same explicit native metadata reference already used by ProposalBuilderService.
    JrcCrm::BusinessUnit.where(account_id: resource.account_id).find_by(id: resource.metadata['business_unit_id'])
  end

  def self.capture(resource)
    commercial = commercial_resource(resource)
    raise JrcApprovals::Error, 'INVALID_CONTEXT' unless commercial.account_id == resource.account_id &&
      business_unit(commercial)&.id == business_unit(resource)&.id

    unit = business_unit(resource)
    raise JrcApprovals::Error, 'INVALID_SCOPE' unless unit

    context = JrcApprovals::NativePriceContext.new(commercial).call
    company = commercial.is_a?(JrcCrm::Proposal) ? commercial.customer_company : commercial.contact&.company
    raise JrcApprovals::Error, 'INVALID_CONTEXT' if company && company.account_id != resource.account_id

    relationship = company&.relationship_type.presence || 'unknown'
    origin = if commercial.is_a?(JrcCrm::SalesOrder)
               commercial.order_origin
             elsif commercial.is_a?(JrcCrm::Proposal) && commercial.relationship_origin['source_contract_id'].present?
               'renewal'
             elsif commercial.is_a?(JrcCrm::Proposal) &&
                   commercial.relationship_origin['relationship_resource_type'] == 'JrcRelationship::ExpansionSignal'
               'expansion'
             else
               'proposal_deal'
             end
    evidence = resource.is_a?(JrcCrm::Contract) ? JrcApprovals::SignatureEvidence.call(resource) :
      { 'state' => 'not_applicable', 'evidence_digest' => nil }
    payload = { 'commercial' => context[:fingerprint_data], 'resource_id' => resource.id,
                'resource_type' => resource.class.name, 'company_id' => unit.company_id, 'unit_id' => unit.id,
                'signature_evidence' => evidence }
    if resource.is_a?(JrcCrm::Contract)
      payload['contract'] = resource.attributes.slice('contract_template_id', 'content_override', 'starts_on', 'ends_on',
        'term_months', 'source_contract_id', 'contract_type')
    end
    { issuer_company_id: unit.company_id, business_unit_id: unit.id,
      values: { price_status: context[:evaluation][:status],
                below_minimum_count: context[:evaluation][:below_minimum_item_indexes].length,
                context_digest: JrcApprovals::Ledger.digest(payload.as_json), signature_evidence: evidence['state'],
                total_cents: context[:valuation].fetch(:total_cents), currency: context[:evaluation][:currency] || 'unavailable',
                item_count: context[:valuation].fetch(:items).length, order_origin: origin, customer_relationship: relationship } }
  end
end
