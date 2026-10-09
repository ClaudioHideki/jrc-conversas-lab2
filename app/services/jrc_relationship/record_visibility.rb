class JrcRelationship::RecordVisibility
  def initialize(context)
    @context = context
  end

  def source_scope(model, relation)
    model == JrcRelationship::Survey ? surveys(relation) : relation
  end

  def expansions(relation, visibility)
    rows = relation.where(deal_id: nil).or(relation.where(deal_id: visibility.crm(@context.account.jrc_crm_deals).select(:id)))
    commercial_returns(rows, visibility)
  end

  def surveys(relation)
    native = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    shared = JrcRelationship::Survey.where(account_id: @context.account.id, assignment_id: nil).or(relation)
    sources = survey_sources(native)
    visible = sources.map { |type, scope| shared.where(source_type: type, source_id: scope.select(:id)) }.reduce(&:or)
    rows = relation.where(source_type: nil).or(visible)
    contracts = native.crm(@context.account.jrc_crm_contracts)
    rows = rows.where(contract_id: nil).or(rows.where(contract_id: contracts.select(:id)))
    native.crm? ? rows : rows.where(product_id: nil)
  end

  def commercial_returns(relation, visibility)
    contracts = visibility.crm(@context.account.jrc_crm_contracts).reselect(:id).reorder(nil).to_sql
    relation.where('NOT EXISTS (SELECT 1 FROM jsonb_array_elements(' \
                   "COALESCE(NULLIF(jrc_relationship_expansion_signals.metadata -> 'commercial_returns', " \
                   "'null'::jsonb), '[]'::jsonb)) AS entry(value) " \
                   "WHERE CASE WHEN entry.value ->> 'contract_id' ~ '^[0-9]+$' THEN (entry.value ->> 'contract_id')::bigint " \
                   "ELSE -1 END NOT IN (#{contracts}))")
  end

  private

  def survey_sources(native)
    sources = { 'Conversation' => native.conversations, 'JrcServiceDesk::Ticket' => native.tickets,
                'JrcRelationship::Qbr' => @context.records(JrcRelationship::Qbr),
                'JrcCrm::Activity' => native.crm(@context.account.jrc_crm_activities, owner: :user_id) }
    calls = native.calls(contact_ids: @context.account.contacts.select(:id), conversation_ids: native.conversations.select(:id))
    sources['Call'] = calls if calls
    sources
  end
end
