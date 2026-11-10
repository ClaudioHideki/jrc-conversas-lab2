class JrcRelationship::SchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('jrc_relationship')
      JrcRelationship::SurveyEventRecovery.new(account).call

      members = account.account_users.includes(:user, :custom_role).index_by(&:user_id)
      JrcRelationship::Assignment.where(account: account).where.not(status: %w[churned inactive]).find_in_batches(batch_size: 200) do |batch|
        batch.group_by(&:owner_id).each do |owner_id, assignments|
          member = members[owner_id]
          policy = member && JrcRelationship::ModulePolicy.new({ account: account, user: member.user, account_user: member }, account)
          if member&.user&.active_for_authentication? && policy&.access?
            JrcRelationship::RefreshJob.perform_later(member.id, assignments.map(&:id))
          else
            monitor_without_owner(account, members.values, assignments.map(&:id))
          end
        end
      end
    end
  end

  private

  def monitor_without_owner(account, members, remaining)
    members.each do |member|
      next unless member.user.active_for_authentication?

      policy = JrcRelationship::ModulePolicy.new({ account: account, user: member.user, account_user: member }, account)
      next unless policy.team?

      authorized = JrcRelationship::Context.new(member).assignments.where(id: remaining).pluck(:id)
      next if authorized.empty?

      JrcRelationship::RefreshJob.perform_later(member.id, authorized)
      remaining -= authorized
      break if remaining.empty?
    end
  end
end
