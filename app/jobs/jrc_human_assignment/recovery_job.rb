class JrcHumanAssignment::RecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.where('custom_attributes @> ?', { jrc_human_assignment: { enabled: true } }.to_json).find_each do |account|
      JrcHumanAssignment::DispatchJob.perform_later(account.id) if account.active?
    end
  end
end
