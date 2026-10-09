class JrcNico::Helpdesk::MonitorJob < ApplicationJob
  queue_as :default

  def perform
    JrcNico::Helpdesk::PolicyVersion.where(state: 'published', enabled: true).find_each do |policy|
      next unless policy.enabled?

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
      JrcNico::Helpdesk::DailyReporter.new(policy).call if policy.definition.dig('daily', 'enabled')
    end
  end
end
