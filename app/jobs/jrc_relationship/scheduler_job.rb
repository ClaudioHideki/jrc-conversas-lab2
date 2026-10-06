class JrcRelationship::SchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      next unless account.feature_enabled?('jrc_relationship')
      members = account.account_users.includes(:user, :custom_role).index_by(&:user_id)
      JrcRelationship::Assignment.where(account: account).where.not(status: %w[churned inactive]).find_in_batches(batch_size: 200) do |batch|
        batch.group_by(&:owner_id).each do |owner_id, assignments|
          member = members[owner_id]
          next unless member && JrcRelationship::ModulePolicy.new({ account: account, user: member.user, account_user: member }, account).access?
          JrcRelationship::RefreshJob.perform_later(member.id, assignments.map(&:id))
        end
      end
    end
  end
end
