require 'json'
require 'digest'

# Pure proof validator. No historic text may be projected unless both the
# captured boundary and every referenced source pass current native authority.
class JrcRelationship::PortfolioHistoryBoundary
  VERSION = 1
  BOUNDARY_FIELDS = %w[owner_id team_id business_unit_id segment_id visibility].freeze
  ORIGIN_FIELDS = %w[id company_id contact_id business_unit_id].freeze
  GROUP_FIELDS = %w[name objective owner_id team_id business_unit_id segment_id visibility status goals customers].freeze
  RULE_FIELDS = %w[portfolio_capacity_limits portfolio_transfer_approval_required portfolio_review_validity_minutes].freeze
  SNAPSHOT_FIELDS = %w[version account_id group_id event_digest boundaries origins before after reason resolved kind].freeze
  class Invalid < StandardError; end

  def self.canonical(value)
    case value
    when Hash then value.transform_keys(&:to_s).sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def self.valid?(snapshot)
    return false unless snapshot.is_a?(Hash) && snapshot.keys.sort == SNAPSHOT_FIELDS.sort
    return false unless snapshot['version'] == VERSION && integer_id?(snapshot['account_id']) && integer_id?(snapshot['group_id'])
    return false unless snapshot['event_digest'].is_a?(String) && snapshot['event_digest'].match?(/\A[0-9a-f]{64}\z/)
    boundaries = snapshot['boundaries']
    return false unless boundaries.is_a?(Array) && boundaries.length.between?(1, 2) && boundaries.all? { |row| valid_boundary?(row) }
    origins = snapshot['origins']
    return false unless origins.is_a?(Array) && origins.all? { |row| valid_origin?(row) }
    return false unless origins.map { |row| row['id'] }.uniq.length == origins.length
    return false unless %w[before after].all? { |key| valid_values?(snapshot[key], snapshot['kind'], origins) }
    return false unless snapshot['reason'].nil? || (snapshot['reason'].is_a?(String) && snapshot['reason'].length <= 4000)

    snapshot['resolved'] == true && %w[group rules].include?(snapshot['kind'])
  end

  def self.valid_boundary?(row)
    row.is_a?(Hash) && row.keys.sort == BOUNDARY_FIELDS.sort &&
      integer_id?(row['owner_id']) && %w[private team account].include?(row['visibility']) &&
      %w[team_id business_unit_id segment_id].all? { |field| row[field].nil? || integer_id?(row[field]) } &&
      (row['visibility'] != 'team' || integer_id?(row['team_id']))
  end

  def self.valid_origin?(row)
    row.is_a?(Hash) && row.keys.sort == ORIGIN_FIELDS.sort && integer_id?(row['id']) &&
      [row['company_id'], row['contact_id']].count { |value| integer_id?(value) } == 1 &&
      %w[company_id contact_id business_unit_id].all? { |key| row[key].nil? || integer_id?(row[key]) }
  end

  def self.valid_values?(value, kind, origins)
    return false unless value.is_a?(Hash)
    return false unless (value.keys - (kind == 'rules' ? %w[version rules] : GROUP_FIELDS)).empty?
    return false unless json_values?(value)
    if kind == 'rules'
      return false unless value['version'].nil? || (value['version'].is_a?(Integer) && value['version'] >= 0)
      rules = value['rules']
      return false unless rules.is_a?(Hash) && (rules.keys - RULE_FIELDS).empty?
      limits = rules['portfolio_capacity_limits']
      return false if limits && (!limits.is_a?(Array) || limits.any? { |row| !valid_limit?(row) })
    elsif value.key?('customers')
      ids = origins.map { |row| row['id'] }
      rows = value['customers']
      return false unless rows.is_a?(Array) && rows.all? do |row|
        row.is_a?(Array) && row.size == 2 && ids.include?(row[0]) && [true, false].include?(row[1])
      end
    end
    goals = value['goals']
    return false if goals && (!goals.is_a?(Array) || goals.any? { |row| !row.is_a?(Hash) || (row.keys - %w[metric baseline target current unit]).any? })

    true
  end

  def self.valid_limit?(row)
    row.is_a?(Hash) && (row.keys - %w[user_id maximum availability dedication unit]).empty? && integer_id?(row['user_id'])
  end

  def self.json_values?(value, depth = 0)
    return false if depth > 8

    case value
    when Hash then value.all? { |key, item| key.is_a?(String) && json_values?(item, depth + 1) }
    when Array then value.all? { |item| json_values?(item, depth + 1) }
    when String, Integer, TrueClass, FalseClass, NilClass then true
    when Float then value.finite?
    else false
    end
  end

  def self.integer_id?(value)
    value.is_a?(Integer) && value.positive?
  end

  def initialize(account_id:, group_id:, actor_id:, admin:, configure:, team_ids:, unit_allowed:, origins_allowed:, references_allowed:)
    @account_id, @group_id, @actor_id = account_id, group_id, actor_id
    @admin, @configure, @team_ids = admin, configure, team_ids
    @unit_allowed, @origins_allowed, @references_allowed = unit_allowed, origins_allowed, references_allowed
  end

  def allowed?(snapshot, snapshot_digest:, event_digest:)
    return false unless self.class.valid?(snapshot)
    return false unless snapshot['account_id'] == @account_id && snapshot['group_id'] == @group_id
    return false unless self.class.digest(snapshot) == snapshot_digest && snapshot['event_digest'] == event_digest
    return false if snapshot['kind'] == 'rules' && !@configure
    return false unless snapshot['boundaries'].all? { |boundary| boundary_allowed?(boundary) }
    return false unless @origins_allowed.call(snapshot['origins'])

    @references_allowed.call(snapshot)
  end

  private

  def boundary_allowed?(boundary)
    return false unless @unit_allowed.call(boundary['business_unit_id'])
    return true if @admin || boundary['owner_id'] == @actor_id
    return true if boundary['visibility'] == 'account'

    boundary['visibility'] == 'team' && @team_ids.include?(boundary['team_id'])
  end
end
