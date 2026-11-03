# Only the link fields are projected. Audit snapshots and inaccessible companies
# remain private, even when the person is visible in their current company.
class JrcCustomers::CompanyContactHistory
  FIELDS = JrcCustomers::ContactMaster::COMPANY_CONTEXT_FIELDS
  EVENTS = %w[customer_contact_linked customer_contact_primary_changed customer_contact_context_changed].freeze

  def initialize(account:, actor:, contact:)
    @account = account
    @actor = actor
    @contact = contact
  end

  def scope
    JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).find(@contact.id)
    JrcCrm::AuditEvent.where(account_id: @account.id, resource_type: 'Contact', resource_id: @contact.id, event_type: EVENTS)
  end

  def serialize(records)
    companies = visible_companies(records)
    actors = @account.users.where(id: records.select { |event| event.actor_type == 'User' }.map(&:actor_id)).pluck(:id, :name).to_h
    records.map do |event|
      { id: event.id, at: event.created_at, kind: event.event_type, actor_name: event.actor_type == 'User' ? actors[event.actor_id] : nil,
        from: context(event.from_value, companies), to: context(event.to_value, companies) }
    end
  end

  private

  def visible_companies(records)
    snapshots = records.flat_map { |event| [event.from_value, event.to_value] }.select { |value| value.is_a?(Hash) }
    ids = snapshots.filter_map { |value| value['company_id'] }
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @actor)
    coverage.companies(@account.master_companies.where(id: ids)).pluck(:id, :name).to_h
  end

  def context(snapshot, companies)
    return nil unless snapshot.is_a?(Hash)
    return { restricted: true } if snapshot['company_id'].present? && !companies.key?(snapshot['company_id'])

    snapshot.slice(*FIELDS).merge('company_name' => companies[snapshot['company_id']])
  end
end
