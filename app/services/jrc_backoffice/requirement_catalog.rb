require 'securerandom'

class JrcBackoffice::RequirementCatalog
  class Conflict < StandardError; end
  SCOPE_FIELDS = %w[business_unit_id product_id operation customer_kind].freeze

  def self.lock!(account_id)
    # Catalog publication and plan capture see the same versioned configuration.
    sql = ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?, ?)', 628119, Integer(account_id)])
    ActiveRecord::Base.connection.execute(sql)
  end

  def self.latest(account_id)
    JrcBackoffice::RequirementRule.where(account_id: account_id)
                                .select('DISTINCT ON (rule_key) jrc_backoffice_requirement_rules.*')
                                .order(:rule_key, version: :desc).to_a
  end

  def self.matching(request)
    products = request.sales_order.order_items.distinct.pluck(:product_id)
    kind = customer_kind(request)
    latest(request.account_id).select do |rule|
      rule.state == 'active' && (rule.operation.nil? || rule.operation == request.request_kind) &&
        (rule.business_unit_id.nil? || rule.business_unit_id == request.business_unit_id) &&
        (rule.product_id.nil? || products.include?(rule.product_id)) &&
        (rule.customer_kind.nil? || kind.nil? || rule.customer_kind == kind)
    end
  end

  def self.customer_kind(request)
    identifier = JrcCustomers::TaxIdentifier.normalize(request.contact&.company&.tax_id)
    return nil unless identifier
    return 'company' if JrcCustomers::TaxIdentifier.cnpj_valid?(identifier)
    return 'individual' if JrcCustomers::TaxIdentifier.cpf_valid?(identifier)

    nil
  end

  def initialize(account:, actor:)
    @account, @actor = account, actor
  end

  def index(page: 1, query: '')
    authorize!
    inner = JrcBackoffice::RequirementRule.where(account_id: @account.id)
      .select('DISTINCT ON (rule_key) jrc_backoffice_requirement_rules.*').order(:rule_key, version: :desc)
    rows = JrcBackoffice::RequirementRule.from("(#{inner.to_sql}) AS jrc_backoffice_requirement_rules")
    text = query.to_s.strip
    raise ArgumentError, 'Search is too long' if text.length > 200

    rows = rows.where("definition ->> 'label' ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(text)}%") unless text.empty?
    total = rows.count
    pages = [(total / 20.0).ceil, 1].max
    number = Integer(page.to_s, 10).clamp(1, pages)
    data = rows.order(:rule_key).offset((number - 1) * 20).limit(20).includes(:product, :business_unit).map { |row| present(row) }
    authorize!
    { data: data, can_manage: true, meta: { page: number, per_page: 20, total: total, pages: pages } }
  end

  def options(kind:, query:, page:)
    authorize!
    relation = case kind
               when 'products' then @account.jrc_crm_products.where(active: true)
               when 'units' then @account.jrc_crm_business_units.where(active: true)
               when 'reviewers' then @account.users
               when 'reviewer_teams' then @account.teams
               else raise ArgumentError, 'Unsupported scope kind'
               end
    text = query.to_s.strip
    raise ArgumentError, 'Search is too long' if text.length > 200

    relation = relation.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(text)}%") unless text.empty?
    number = Integer(page.to_s, 10).clamp(1, 10000)
    count = relation.count
    rows = relation.order(:name, :id).limit(25).offset((number - 1) * 25).pluck(:id, :name)
    authorize!
    { data: rows.map { |id, name| { id: id, name: name } }, meta: { page: number, per_page: 25, total: count } }
  end

  def save!(rule_key:, expected_version:, attributes:, reason:)
    raise ArgumentError, 'Provide an explicit change reason' unless JrcBackoffice::RequirementDefinition.text?(reason, 4000)
    raise ArgumentError, 'Revision must be a non-negative integer' unless expected_version.is_a?(Integer) && expected_version >= 0

    attrs = attributes.to_h.stringify_keys
    raise ArgumentError, 'Unsupported catalog fields' unless (attrs.keys - SCOPE_FIELDS - %w[definition state]).empty?
    definition = JrcBackoffice::RequirementDefinition.normalize(attrs.fetch('definition'))
    JrcBackoffice::RequirementRule.transaction do
      self.class.lock!(@account.id)
      authorize!
      key = rule_key.presence || SecureRandom.uuid
      previous = JrcBackoffice::RequirementRule.where(account: @account, rule_key: key).order(version: :desc).first
      if previous && expected_version.zero? && previous.version == 1 && previous.created_by_id == @actor.id &&
         previous.definition == definition && previous.state == attrs.fetch('state', 'active') && previous.reason == reason.strip &&
         SCOPE_FIELDS.all? { |field| previous.public_send(field) == normalize_scope(attrs)[field] }
        return present(previous)
      end
      raise Conflict, 'Requirement rule changed; reload before saving' unless (previous&.version || 0) == expected_version
      if previous && SCOPE_FIELDS.any? { |field| normalize_scope(attrs)[field] != previous.public_send(field) }
        raise ArgumentError, 'Archive the old rule and create another to change its scope'
      end
      record = JrcBackoffice::RequirementRule.create!(normalize_scope(attrs).merge(
        account: @account, created_by: @actor, rule_key: key, version: expected_version + 1,
        state: attrs.fetch('state', 'active'), definition: definition, reason: reason.strip
      ))
      verify_references!(record)
      JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id,
        event_type: 'operations_configured', resource_type: record.class.name, resource_id: record.id,
        from_value: { version: expected_version }, to_value: { version: record.version, rule_key: key, state: record.state },
        metadata: { source: 'backoffice_requirement_catalog' })
      authorize!
      present(record)
    end
  end

  private

  def authorize!
    raise Pundit::NotAuthorizedError unless JrcBackoffice::SignatureConfiguration.can_manage?(account: @account, actor: @actor)
  end

  def normalize_scope(attributes)
    result = attributes.slice(*SCOPE_FIELDS)
    %w[business_unit_id product_id].each do |field|
      value = result[field]
      raise ArgumentError, 'Scope reference must be an integer or null' unless value.nil? || (value.is_a?(Integer) && value.positive?)
    end
    result
  end

  def verify_references!(rule)
    @account.jrc_crm_business_units.find(rule.business_unit_id) if rule.business_unit_id
    @account.jrc_crm_products.find(rule.product_id) if rule.product_id
    reviewers = Array(rule.definition['reviewer_ids'])
    teams = Array(rule.definition['reviewer_team_ids'])
    raise ActiveRecord::RecordNotFound unless @account.users.where(id: reviewers).count == reviewers.length
    raise ActiveRecord::RecordNotFound unless @account.teams.where(id: teams).count == teams.length
    Array(rule.definition['conditions']).each do |condition|
      values = condition['operator'] == 'in' ? condition['value'] : [condition['value']]
      relation = case condition['field']
                 when 'business_unit_id' then @account.jrc_crm_business_units
                 when 'product_id' then @account.jrc_crm_products
                 end
      raise ActiveRecord::RecordNotFound if relation && relation.where(id: values.uniq).count != values.uniq.size
    end
  end

  def present(row)
    row.attributes.slice('rule_key', 'version', 'state', 'definition', *SCOPE_FIELDS).merge(
      'product' => row.product && { 'id' => row.product.id, 'name' => row.product.name },
      'business_unit' => row.business_unit && { 'id' => row.business_unit.id, 'name' => row.business_unit.name }
    )
  end
end
