# Called only inside the existing exclusive, guarded synthetic account seeder.
class JrcContactCenter::SyntheticStateHistorySeed
  def self.call(account:, member:, queues:)
    now = Time.current
    visible = 25.times.map do |index|
      JrcContactCenter::AgentStateEvent.create!(
        account: account, account_user: member, queue: queues.first, state: 'paused', source: 'jrc_conversas',
        started_at: now - (index + 2).minutes, ended_at: now - (index + 1).minutes,
        reason_code: 'SYNTHETIC_PRIVATE_HISTORY_REASON',
        metadata: { provider_confirmed: false, pause_justification: 'SYNTHETIC_PRIVATE_HISTORY_TEXT' }
      ).id.to_s
    end
    denied = JrcContactCenter::AgentStateEvent.create!(
      account: account, account_user: member, queue: queues.last, state: 'offline', source: 'jrc_conversas', started_at: now
    )
    unbound = JrcContactCenter::AgentStateEvent.create!(
      account: account, account_user: member, state: 'available', source: 'jrc_conversas', started_at: now
    )
    { history_visible_ids: visible, history_denied_id: denied.id.to_s, history_unbound_id: unbound.id.to_s }
  end
end
