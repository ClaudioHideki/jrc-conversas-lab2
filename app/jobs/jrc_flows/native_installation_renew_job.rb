class JrcFlows::NativeInstallationRenewJob < ApplicationJob
  queue_as :scheduled_jobs
  def perform
    JrcFlowNativeInstallation.where(state: 'REVOKED', remote_revoke_pending: true).limit(100).find_each do |row|
      JrcFlows::NativeInstallations.new(account_id: row.account_id, user_id: row.created_by_id).revoke!(row.grant_id)
    rescue JrcFlows::NativeClient::Error, JrcFlows::NativeIntrospection::Denied
      Rails.logger.warn("Flow installation reduction pending id=#{row.id}")
    end
    JrcFlowNativeInstallation.where(state: %w[ACTIVE RENEWING UNKNOWN])
                            .where('expires_at>clock_timestamp() AND (lease_until IS NULL OR lease_until<=clock_timestamp())')
                            .limit(100).find_each do |row|
      JrcFlows::NativeInstallations.new(account_id: row.account_id, user_id: row.created_by_id).renew!(row.id)
    rescue JrcFlows::NativeClient::Error, JrcFlows::NativeIntrospection::Denied
      # Same persisted operation only; no framework retry creates a new POST.
      Rails.logger.warn("Flow installation renewal pending id=#{row.id}")
    end
  end
end
