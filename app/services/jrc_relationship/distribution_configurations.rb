# Hard distribution constraints accumulate. A product/segment override must not
# silently disable a parent account/unit requirement. Health resolution is unchanged.
class JrcRelationship::DistributionConfigurations
  def initialize(account)
    @account = account
    @configurations = JrcRelationship::Configuration.where(account_id: account.id).index_by(&:scope_key)
  end

  def for(record)
    raise ActiveRecord::RecordNotFound unless record.account_id == @account.id

    keys = ['account', "unit:#{record.business_unit_id}", "company:#{record.company_id}", "team:#{record.team_id}",
            "segment:#{record.settings['segment_id']}", "product:#{record.settings['product_id']}"]
    matches = keys.filter_map { |key| @configurations[key] }
    matches.presence || [JrcRelationship::Configuration.new(account: @account, scope_key: 'account')]
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
    else raise ArgumentError, 'Unsupported distribution scope'
    end
  end
end
