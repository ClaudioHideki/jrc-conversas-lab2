# frozen_string_literal: true

# Optional, voice-only rules inside the existing Account ACW policy. No new registry.
class JrcContactCenter::AcwScopedRules
  KEY = 'voice_rules'

  def initialize(account:)
    @account = account
  end

  def call
    input = @account.settings.fetch(JrcContactCenter::AcwPolicy::KEY, {}).fetch(KEY, [])
    JrcContactCenter::AcwRulePrecedence.new(rules: input).rules
  end

  def validate!(input)
    rows = JrcContactCenter::AcwRulePrecedence.new(rules: input).rules
    active = rows.select { |row| row.fetch('active') }
    keys = active.map { |row| row.values_at('reason_code', 'scope', 'scope_id') }
    raise JrcContactCenter::OperationError, 'conflicting_acw_rules' unless keys.uniq.length == keys.length

    verify_references!(rows)
    rows
  end

  private

  def verify_references!(rows)
    %w[queue team].each do |scope|
      ids = rows.select { |row| row.fetch('scope') == scope }.pluck('scope_id').uniq
      relation = scope == 'queue' ? JrcContactCenter::Queue.where(account: @account) : @account.teams
      found = relation.where(id: ids).pluck(:id).map(&:to_s)
      raise ActiveRecord::RecordNotFound unless ids.sort == found.sort
    end
  end

end
