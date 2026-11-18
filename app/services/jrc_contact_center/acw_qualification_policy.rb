# frozen_string_literal: true

# New qualifications capture their own trusted rule context. Old events are not rewritten.
class JrcContactCenter::AcwQualificationPolicy
  KEY = 'acw_rule_snapshot_v1'

  def self.capture(record, member:, leg:)
    new(record).capture(member: member, leg: leg)
  end

  def initialize(record)
    @record = record
  end

  def capture(member:, leg:)
    return {} unless @record.channel == 'voice'

    rules = JrcContactCenter::AcwScopedRules.new(account: @record.account).call
    return {} if rules.empty?

    context = native_context(member, leg)
    rules = rules.select { |row| applicable?(row, context) }
    values = context.merge(
      'account_id' => @record.account_id, 'account_user_id' => member.id, 'qualification_id' => @record.id,
      'rules' => rules, 'revision' => JrcContactCenter::AcwPolicy.new(account: @record.account).revision,
      'default_limit_seconds' => @record.acw_limit_seconds
    )
    { KEY => values }
  end

  def limit(reason)
    snapshot = stored
    return @record.acw_limit_seconds unless snapshot

    selected = JrcContactCenter::AcwRulePrecedence.new(rules: snapshot.fetch('rules')).call(
      reason_code: reason, queue_id: snapshot.fetch('queue_id'), team_ids: snapshot.fetch('team_ids')
    )
    selected ? selected.fetch('limit_seconds') : snapshot.fetch('default_limit_seconds')
  end

  private

  def native_context(member, leg)
    queue_id = leg&.queue_id
    # Use the answered leg's native origin, never the transferred call's current queue.
    queue_id = JrcContactCenter::Queue.where(account: @record.account).find(queue_id).id if queue_id
    teams = @record.account.teams.joins(:team_members).where(team_members: { user_id: member.user_id }).distinct.pluck(:id).map(&:to_s)
    { 'queue_id' => queue_id, 'team_ids' => teams }
  end

  def applicable?(row, context)
    return false unless row.fetch('active')
    return true if row.fetch('scope') == 'general'
    return row.fetch('scope_id') == context.fetch('queue_id').to_s if row.fetch('scope') == 'queue'

    context.fetch('team_ids').include?(row.fetch('scope_id'))
  end

  def stored
    event = JrcContactCenter::AgentStateEvent.find_by(
      account_id: @record.account_id, account_user_id: @record.account_user_id,
      external_event_id: "qualification:#{@record.id}:pending"
    )
    return unless event&.metadata&.key?(KEY)

    snapshot = event.metadata.fetch(KEY)
    expected = { 'account_id' => @record.account_id, 'account_user_id' => @record.account_user_id, 'qualification_id' => @record.id }
    raise JrcContactCenter::OperationError, 'invalid_acw_rule_snapshot' unless snapshot.is_a?(Hash) && snapshot.slice(*expected.keys) == expected

    snapshot
  end
end
