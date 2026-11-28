# Read-only enrichment of the native contact list. Keep CRM and inbox data
# behind their respective visibility rules.
class JrcCustomers::ContactDirectoryList
  def initialize(account:, actor:, membership:, scope:)
    @account = account
    @actor = actor
    @membership = membership
    @scope = scope
  end

  def filter(relation, owner:, inbox_id:)
    if owner.present? && directory_access?
      relation = relation.where(company_id: companies.where(owner_id: owner).reselect(:id))
    end
    return relation if inbox_id.blank?

    relation.where(id: links.where(inbox_id: inbox_id).select(:contact_id))
  end

  def matching_company_ids(term)
    return @account.master_companies.none.select(:id) unless directory_access?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    companies.where('name ILIKE :q OR trade_name ILIKE :q OR customer_code ILIKE :q', q: pattern).select(:id)
  end

  def summary
    zone = Time.find_zone(@account.reporting_timezone) || Time.zone
    month_start = Time.current.in_time_zone(zone).beginning_of_month
    sql = ApplicationRecord.sanitize_sql_array(
      [<<~SQL.squish, month_start, 30.days.ago]
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE contacts.created_at >= ?) AS new_this_month,
        COUNT(*) FILTER (WHERE contacts.last_activity_at IS NULL OR contacts.last_activity_at < ?) AS inactive
      SQL
    )
    relation = @scope.reorder(nil)
    totals = ApplicationRecord.connection.select_one(relation.select(Arel.sql(sql)).to_sql)
    linked = relation.where(company_id: companies.reselect(:id)).count if directory_access?
    totals.merge('linked' => linked)
  end

  def details(records)
    ids = records.map(&:id)
    return {} if ids.empty?

    inboxes = links.where(contact_id: ids).pluck(:contact_id, :inbox_id).group_by(&:first)
    return records.index_with { |contact| channels(inboxes, contact.id) }.transform_keys(&:id) unless directory_access?

    companies_by_id = companies.where(id: records.map(&:company_id).compact).pluck(:id, :name, :owner_id).index_by(&:first)
    names = @account.users.where(id: companies_by_id.values.pluck(2).compact).pluck(:id, :name).to_h
    actions = JrcCustomers::OperationalContacts.new(account: @account, actor: @actor).next_actions(ids)
    records.to_h do |contact|
      _, company_name, owner_id = companies_by_id[contact.company_id]
      [contact.id, channels(inboxes, contact.id).merge(company_name: company_name, owner_name: names[owner_id], next_action: actions[contact.id])]
    end
  end

  private

  def channels(inboxes, id)
    { inbox_ids: inboxes.fetch(id, []).map(&:last).uniq }
  end

  def directory_access?
    @directory_access ||= JrcCustomers::DirectoryPolicy.new(
      { account: @account, user: @actor, account_user: @membership }, :directory
    ).access?
  end

  def companies
    @companies ||= JrcCrm::CorporateCoverage.new(account: @account, user: @actor).companies(@account.master_companies)
  end

  def links
    return ContactInbox.none unless @actor.is_a?(User)

    ContactInbox.where(inbox_id: @actor.assigned_inboxes.where(account_id: @account.id).reselect(:id))
  end
end
