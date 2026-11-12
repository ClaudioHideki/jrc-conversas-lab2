require 'digest'

# A bounded wait requires an operational review even while its native SLA is
# paused. This records an internal notice; it never resumes or completes work.
class JrcRelationship::WaitingReviewMonitor
  def initialize(account_id: nil)
    @account_id = account_id
  end

  def call
    rows = JrcRelationship::Action.where(status: JrcRelationship::Action::WAITING_STATUSES).where('return_at <= ?', Time.current)
    rows = rows.where(account_id: @account_id) if @account_id
    rows.includes(:account).find_each { |action| review(action) }
  end

  private

  def review(action)
    action.with_lock do
      next unless due?(action)

      key = Digest::SHA256.hexdigest([action.id, action.owner_id, action.status, action.return_at.utc.iso8601(6)].join(':'))
      receipts = JrcCrm::AuditEvent.where(account: action.account, resource_type: action.class.name, resource_id: action.id,
                                          event_type: 'relationship_updated').where("metadata ->> 'waiting_review_notice_key' = ?", key)
      next if receipts.exists?

      JrcRelationship::Notifications.call(action, event: "waiting_review_due:#{key}")
      receipts.create!(actor_type: 'System', from_value: {}, to_value: { status: action.status, return_at: action.return_at.utc.iso8601(6) },
                       metadata: { action: 'waiting_review_due', assignment_id: action.assignment_id, waiting_review_notice_key: key })
    end
  end

  def due?(action)
    action.account.active? && action.account.feature_enabled?('jrc_relationship') &&
      JrcRelationship::Action::WAITING_STATUSES.include?(action.status) && action.return_at && action.return_at <= Time.current
  end
end
