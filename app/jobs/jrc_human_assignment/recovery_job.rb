class JrcHumanAssignment::RecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where("custom_attributes ? 'jrc_human_assignment'").find_each do |account|
      JrcHumanAssignment::DispatchJob.perform_later(account.id) if account.active? && JrcHumanAssignment::Policy.enabled?(account)
    end
  end
end
