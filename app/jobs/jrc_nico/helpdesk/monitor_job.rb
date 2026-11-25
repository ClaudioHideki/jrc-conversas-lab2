class JrcNico::Helpdesk::MonitorJob < ApplicationJob
  queue_as :default

  def perform
    JrcNico::Helpdesk::PolicyVersion.where(state: 'published', enabled: true).find_each do |policy|
      next unless policy.enabled?

      started_at = Time.current
      capture_policy(policy)
      recover_detected(policy, started_at)
      JrcNico::Helpdesk::DailyReporter.new(policy).call if policy.definition.dig('daily', 'enabled')
    end
  end

  private

  def capture_policy(policy)
    policy.definition.fetch('operator_ids').each do |id|
      member = policy.account.account_users.find_by(id: id)
      next unless member

      context = JrcNico::Helpdesk::Context.new(member)
      context.tickets.where(unit_id: policy.definition.fetch('unit_ids'), company_id: policy.definition.fetch('company_ids')).find_each do |ticket|
        JrcNico::Helpdesk::Capture.call(ticket: ticket, trigger: 'monitor', origin_key: "monitor:#{Time.current.utc.strftime('%Y%m%d%H%M')}",
                                        member: member)
      end
    rescue Pundit::NotAuthorizedError
      next
    end
  end

  def recover_detected(policy, started_at)
    # No Event backfill: only a current native Capture may create an intent.
    # New intents queued during this pass are excluded from its recovery scan.
    pending = JrcNico::Helpdesk::DispatchIntent.joins(:event).where(account_id: policy.account_id)
    pending.where(jrc_nico_helpdesk_events: { policy_version_id: policy.id, state: 'detected' })
           .where('jrc_nico_helpdesk_dispatch_intents.created_at < ?', started_at).includes(:event).find_each do |intent|
      JrcNico::Helpdesk::EventDispatch.call(intent.event)
    end
  end
end
