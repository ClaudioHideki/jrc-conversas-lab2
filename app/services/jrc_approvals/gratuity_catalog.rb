# Shares the existing approval engine; price v1 snapshots and policies stay unchanged.
class JrcApprovals::GratuityCatalog
  FAMILY = 'crm.gratuity_request'.freeze
  EVENTS = { 'crm.deal_gratuity' => 'JrcCrm::Deal', 'crm.proposal_gratuity' => 'JrcCrm::Proposal',
             'crm.order_gratuity' => 'JrcCrm::SalesOrder' }.freeze
  FIELDS = JrcApprovals::CommercialCatalog::FIELDS.merge(
    'has_commercial_gratuity' => 'boolean', 'gratuity_item_count' => 'integer', 'gratuity_type' => 'string_list',
    'gratuity_total_cents' => 'integer', 'below_minimum_total_cents' => 'integer', 'discount_percentage' => 'decimal',
    'company_id' => 'integer', 'approval_context_version' => 'integer', 'gratuity_value_status' => 'string'
  ).freeze

  def self.key_for(resource)
    EVENTS.key(JrcApprovals::CommercialCatalog.commercial_resource(resource).class.name)
  end

  def self.required?(resource)
    commercial = JrcApprovals::CommercialCatalog.commercial_resource(resource)
    key_for(resource) && JrcApprovals::CommercialCatalog.business_unit(commercial)&.company_id &&
      JrcApprovals::CommercialGratuity.new(resource: commercial).call[:has_commercial_gratuity]
  end

  def self.gratuity_key?(key)
    EVENTS.key?(key) || key == FAMILY
  end

  def self.install!
    EVENTS.each do |key, name|
      model = name.constantize
      existing = JrcApprovals::Catalog.instance_variable_get(:@entries)[key]
      next if existing && existing.model.equal?(model)

      JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize do
        JrcApprovals::Catalog.instance_variable_get(:@entries).delete(key)
      end

      JrcApprovals::Catalog.register(key: key, version: 1, model: model, fields: FIELDS,
                                     authorize: lambda { |user, resource|
                                       JrcApprovals::CommercialCatalog.authorized?(user, resource)
                                     },
                                     capture: ->(resource) { capture(resource) })
    end
    return if JrcApprovals::Catalog.instance_variable_get(:@entries).key?(FAMILY)

    JrcApprovals::Catalog.register(key: FAMILY, version: 1, model: nil, fields: FIELDS, policy_only: true,
                                   authorize: ->(*) { false }, capture: ->(*) { raise JrcApprovals::Error, 'POLICY_TEMPLATE_ONLY' })
  end

  def self.capture(resource)
    context = JrcApprovals::CommercialCatalog.capture(resource)
    facts = JrcApprovals::CommercialGratuity.new(resource: resource).call
    evidence = facts.delete(:evidence)
    unit = JrcApprovals::CommercialCatalog.business_unit(resource)
    raise JrcApprovals::Error, 'INVALID_SCOPE' unless unit&.company_id

    context[:values].merge!(facts.merge(company_id: unit.company_id))
    context[:values][:context_digest] = JrcApprovals::Ledger.digest(
      price_digest: context[:values][:context_digest], gratuity: facts, evidence: evidence,
      company_authorities: JrcApprovals::GratuityAuthorities.new(account: resource.account, company_id: unit.company_id).profile,
      corporate_authorities: JrcApprovals::GratuityAuthorities.new(account: resource.account, company_id: nil).profile
    )
    context
  end
end
