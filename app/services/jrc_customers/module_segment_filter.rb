# Consumes an already authorized module relation. A published segment narrows the
# view; it never replaces that module's permissions or grants record access.
class JrcCustomers::ModuleSegmentFilter
  def initialize(account:, actor:, module_key:, segment_id:)
    raise ArgumentError, 'Unsupported segment module' unless JrcCustomers::Taxonomy::MODULES.include?(module_key)

    @account = account
    @actor = actor
    @module_key = module_key
    @segment_id = segment_id
  end

  def call(relation, company_column: nil, contact_column: nil)
    return relation if @segment_id.nil? || @segment_id == ''

    validate_id!
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).authorize!
    taxonomy = JrcCustomers::Taxonomy.active.where(account_id: @account.id, kind: 'segment')
                                     .where('? = ANY(modules)', @module_key).find(@segment_id)
    members = JrcCustomers::SegmentMembers.new(account: @account, actor: @actor, taxonomy: taxonomy)
    relation.where(account_id: @account.id).where(member_predicate(relation, members, company_column, contact_column))
  end

  private

  def member_predicate(relation, members, company_column, contact_column)
    table = relation.klass.arel_table
    predicate = nil
    predicate = table[company_column].in(members.companies.reselect(:id).arel) if company_column
    if contact_column
      contacts = table[contact_column].in(members.contacts.reselect(:id).arel)
      predicate = predicate ? contacts.or(table[contact_column].eq(nil).and(predicate)) : contacts
    end
    raise ArgumentError, 'A canonical customer link is required for segment filtering' unless predicate

    predicate
  end

  def validate_id!
    valid = @segment_id.is_a?(String) || @segment_id.is_a?(Integer)
    text = @segment_id.to_s
    valid &&= text.match?(/\A[1-9][0-9]{0,18}\z/) && text.to_i <= 9_223_372_036_854_775_807
    raise ActionController::BadRequest, 'Invalid customer segment ID' unless valid
  end
end
