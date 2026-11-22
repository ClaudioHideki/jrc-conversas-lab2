# frozen_string_literal: true

# Private details require current authority and the original still-applicable selection.
class JrcContactCenter::DeferredPauseProjection
  def initialize(account:, member:)
    @account = account
    @member = member
  end

  def call(record)
    return unless record
    raise ActiveRecord::RecordNotFound unless record.account_id == @account.id && record.account_user_id == @member.id

    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      context = { account: @account, account_user: @member, user: @member.user }
      next unless @member.user.reload.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?

      payload = record.operator_payload
      next payload.merge('private_details_available' => true).merge(approval_payload(record)) if details_available?(record)

      payload.except('reason_code', 'reason_label', 'queue_id', 'justification').merge('private_details_available' => false)
    end
  end

  private

  def approval_payload(record)
    return {} unless %w[pending blocked].include?(record.state)

    return {} unless JrcContactCenter::PauseApprovalReview.exists?(account: @account, deferred_pause_request_id: record.id)

    status = JrcContactCenter::PauseApprovalReadiness.new(account: @account, member: @member).call(record)
    { 'approval' => status }
  end

  def details_available?(record)
    return false unless record.actor_user_id == @member.user_id

    values = record.attributes.symbolize_keys.slice(:reason_code, :queue_id, :justification)
    current = JrcContactCenter::DeferredPauseSelection.new(account: @account, member: @member).call(values)
    current[:catalog_revision] == record.catalog_revision
  rescue ActiveRecord::RecordNotFound, JrcContactCenter::OperationError
    false
  end
end
