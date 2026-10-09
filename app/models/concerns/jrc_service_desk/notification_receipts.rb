# frozen_string_literal: true

module JrcServiceDesk::NotificationReceipts
  extend ActiveSupport::Concern
  included do
    after_update_commit :reconcile_service_desk_receipt, if: -> { content_attributes.to_h['service_desk_delivery_id'].present? }
    after_update_commit :record_service_desk_first_response, if: lambda {
      outgoing? && !private? && (saved_change_to_source_id? || (saved_change_to_status? && %w[delivered read].include?(status)))
    }
  end

  private

  def reconcile_service_desk_receipt
    JrcServiceDesk::NotificationReconciliationJob.perform_later(id)
  end

  def record_service_desk_first_response
    return unless account.feature_enabled?('jrc_service_desk')

    JrcServiceDesk::FirstResponseJob.perform_later(id, JrcServiceDesk::NativeResponseRecorder.evidence(self))
  end
end
