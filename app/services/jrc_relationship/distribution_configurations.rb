# Hard distribution constraints accumulate. A product/segment override must not
# silently disable a parent account/unit requirement. Health resolution is unchanged.
class JrcRelationship::DistributionConfigurations
  def initialize(account)
    @account = account
    @configurations = JrcRelationship::Configuration.where(account_id: account.id).index_by(&:scope_key)
    @portfolio_ids = @configurations.keys.filter_map { |key| key.split(':', 2).last.to_i if key.start_with?('portfolio:') }
    @portfolio_ids = JrcRelationship::PortfolioGroup.where(account: account, id: @portfolio_ids, status: 'active').pluck(:id) if @portfolio_ids.any?
    @memberships = {}
  end

  def for(record)
    raise ActiveRecord::RecordNotFound unless record.account_id == @account.id

    keys = ['account', "unit:#{record.business_unit_id}", "company:#{record.company_id}", "team:#{record.team_id}",
            "segment:#{record.settings['segment_id']}", "product:#{record.settings['product_id']}"]
    preload([record])
    keys.concat(@memberships.fetch(record.id, []).map { |id| "portfolio:#{id}" })
    matches = keys.filter_map { |key| @configurations[key] }
    matches.presence || [JrcRelationship::Configuration.new(account: @account, scope_key: 'account')]
  end

  def preload(records)
    return self if @portfolio_ids.empty?

    ids = records.filter_map(&:id).uniq - @memberships.keys
    return self if ids.empty?

    ids.each { |id| @memberships[id] = [] }
    links = JrcRelationship::PortfolioGroupAssignment.where(account_id: @account.id, portfolio_group_id: @portfolio_ids,
                                                            assignment_id: ids, active: true)
    links.order(:portfolio_group_id).pluck(:assignment_id, :portfolio_group_id).each { |id, group| @memberships.fetch(id) << group }
    self
  end

  def portfolio_reference(configuration)
    return {} unless configuration.scope_key.start_with?('portfolio:')

    groups = JrcRelationship::PortfolioGroup.where(account_id: @account.id, id: @portfolio_ids)
    versions = @portfolio_versions ||= groups.pluck(:id, :lock_version).to_h
    { 'portfolio_revision' => versions.fetch(configuration.scope_key.split(':', 2).last.to_i) }
  end

  def relation(configuration)
    rows = JrcRelationship::Assignment.where(account_id: @account.id)
    kind, id = configuration.scope_key.split(':')
    case kind
    when 'unit' then rows.where(business_unit_id: id)
    when 'company' then rows.where(company_id: id)
    when 'team' then rows.where(team_id: id)
    when 'segment', 'product' then rows.where('settings ->> ? = ?', "#{kind}_id", id)
    when 'account' then rows
    when 'portfolio'
      links = JrcRelationship::PortfolioGroupAssignment.where(account_id: @account.id, portfolio_group_id: id, active: true)
      rows.where(id: links.select(:assignment_id))
    else raise ArgumentError, 'Unsupported distribution scope'
    end
  end
end
