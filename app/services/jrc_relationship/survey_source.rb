class JrcRelationship::SurveySource
  TYPES = %w[Conversation JrcServiceDesk::Ticket JrcRelationship::Qbr Call JrcCrm::Activity].freeze
  attr_reader :source, :context

  def initialize(source, context, contract_id: nil, product_id: nil)
    @source = source
    @context = context
    @commercial_ids = { 'contract' => contract_id, 'product' => product_id }
    validate_source!
    validate_attendance! if source.is_a?(JrcCrm::Activity)
  end

  def contact
    case source.class.name
    when 'JrcServiceDesk::Ticket' then source.requester
    when 'JrcRelationship::Qbr'
      return unless source.contact_id

      source.assignment.customer_context(context.member).contacts.find(source.contact_id)
    else source.contact
    end
  end

  def assignment
    return source.assignment if source.is_a?(JrcRelationship::Qbr)
    return context.assignment(source.metadata['relationship_attendance_assignment_id']) if source.is_a?(JrcCrm::Activity)

    identity = contact&.company_id ? { company_id: contact.company_id } : { contact_id: contact&.id }
    context.assignments.find_by(identity)
  end

  def completed?
    case source.class.name
    when 'Conversation' then source.resolved?
    when 'JrcServiceDesk::Ticket' then %w[resolved closed].include?(source.status.phase)
    when 'JrcRelationship::Qbr', 'Call' then source.status == 'completed'
    when 'JrcCrm::Activity'
      source.status == 'completed' && source.completed_at.present? && JrcRelationship::ManualAttendance.eligible?(source)
    end
  end

  def attributes
    conversation = source.is_a?(Conversation) ? source : source.try(:conversation)
    { 'source_type' => source.class.name, 'company_id' => contact&.company_id,
      'unit_id' => ticket_unit_id,
      'team_id' => source_team_id(conversation),
      'inbox_id' => conversation&.inbox_id, **commercial_attributes,
      'channel_type' => channel_type(conversation) }
  end

  def contract
    commercial_context[:contract]
  end

  def product
    commercial_context[:product]
  end

  def commercial_origin_signature
    contract_id = native_commercial_id('contract')
    product_id = native_commercial_id('product')
    fallback = fallback_product_id(contract_id)
    { 'contract_id' => contract_id&.to_s, 'product_id' => product_id&.to_s, 'assignment_product_id' => fallback&.to_s }
  end

  def attendance_origin_signature
    return unless source.is_a?(JrcCrm::Activity)

    source.attributes.slice('contact_id', 'deal_id', 'company_id', 'business_unit_id', 'activity_type').merge(
      'assignment_id' => source.metadata['relationship_attendance_assignment_id'],
      'request_digest' => source.metadata['relationship_attendance_digest'],
      'manual' => source.metadata['relationship_manual_attendance']
    )
  end

  def conversation(channel = 'same', inbox_id: nil)
    current = source.is_a?(Conversation) ? source : source.try(:conversation)
    return current if channel == 'same'
    return unless inbox_id

    scopes = JrcCustomers::Visibility.new(account: context.account, user: context.user, account_user: context.member).conversations
                                     .where(contact_id: contact&.id).joins(:inbox)
    types = channel == 'email' ? ['Channel::Email'] : ['Channel::Whatsapp', 'Channel::TwilioSms']
    scopes.where(inbox_id: inbox_id, inboxes: { channel_type: types }).order(updated_at: :desc, id: :desc).first
  end

  private

  def validate_source!
    raise ArgumentError, 'Unsupported survey source' unless source.persisted? && TYPES.include?(source.class.name)
    raise Pundit::NotAuthorizedError unless source.account_id == context.account.id && context.policy.manage?
    raise Pundit::NotAuthorizedError unless visible_sources&.exists?(id: source.id)
  end

  def visible_sources
    visibility = JrcCustomers::Visibility.new(account: context.account, user: context.user, account_user: context.member)
    case source.class.name
    when 'Conversation' then visibility.conversations
    when 'JrcServiceDesk::Ticket' then visibility.tickets
    when 'JrcRelationship::Qbr' then context.records(JrcRelationship::Qbr)
    when 'JrcCrm::Activity' then visibility.crm(context.account.jrc_crm_activities, owner: :user_id)
    when 'Call'
      visibility.calls(contact_ids: context.account.contacts.select(:id), conversation_ids: visibility.conversations.select(:id))
    end
  end

  def validate_attendance!
    record = context.assignment(source.metadata['relationship_attendance_assignment_id'], write: true)
    customer = record.customer_context(context.member)
    raise Pundit::NotAuthorizedError unless record.business_unit_id == source.business_unit_id && customer.contacts.exists?(id: source.contact_id)

    raise Pundit::NotAuthorizedError unless attendance_deal_matches?(customer.deals.find(source.deal_id))
  end

  def attendance_deal_matches?(deal)
    deal.contact_id == source.contact_id || deal.deal_contacts.exists?(contact_id: source.contact_id) ||
      (source.contact.company_id.present? && deal.company_id == source.contact.company_id)
  end

  def source_team_id(conversation)
    source.try(:team_id) || conversation&.team_id || assignment&.team_id
  end

  def commercial_attributes
    { 'contract_id' => contract&.id, 'product_id' => product&.id }
  end

  def ticket_unit_id
    source.unit_id if source.is_a?(JrcServiceDesk::Ticket)
  end

  def channel_type(conversation)
    case source.class.name
    when 'Call' then "call_#{source.direction}"
    else conversation&.inbox&.channel_type || source.try(:origin_channel) || 'meeting'
    end
  end

  def fallback_product_id(contract_id)
    assignment&.settings&.dig('product_id') unless contract_id || @commercial_ids['contract']
  end

  def commercial_customer
    assignment&.customer_context(context.member) || JrcCustomers::Customer360.new(
      account: context.account, user: context.user, account_user: context.member, contact: contact
    )
  end

  def commercial_context
    return @commercial_context if defined?(@commercial_context)

    contract_id = commercial_id('contract')
    product_id = commercial_product_id(contract_id)
    return @commercial_context = { contract: nil, product: nil } unless contract_id || product_id

    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(context.member)

    customer = commercial_customer
    contract, product = commercial_records(customer, contract_id, product_id)
    validate_product_contract!(contract, product)

    @commercial_context = { contract: contract, product: product }
  end

  def commercial_product_id(contract_id)
    commercial_id('product') || (assignment&.settings&.dig('product_id') unless contract_id)
  end

  def commercial_records(customer, contract_id, product_id)
    contract = customer.contracts.find(contract_id) if contract_id
    product = context.account.jrc_crm_products.find(product_id) if product_id
    [contract, product]
  end

  def validate_product_contract!(contract, product)
    return unless contract && product
    return if contract.contract_items.exists?(product_id: product.id) || contract.sales_order.order_items.exists?(product_id: product.id)

    raise Pundit::NotAuthorizedError
  end

  def commercial_id(kind)
    value = native_commercial_id(kind) || @commercial_ids[kind]
    return if value.blank?

    raise Pundit::NotAuthorizedError unless value.to_s.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def native_commercial_id(kind)
    metadata = source.try(:metadata) || source.try(:meta) || source.try(:additional_attributes) || {}
    source.try("#{kind}_id") || metadata["relationship_#{kind}_id"]
  end
end
