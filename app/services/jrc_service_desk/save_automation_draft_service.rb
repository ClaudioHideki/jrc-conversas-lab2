# frozen_string_literal: true

class JrcServiceDesk::SaveAutomationDraftService < JrcServiceDesk::BaseService
  CAPS = { 'queue' => :queues_manage, 'notification' => :notifications_manage, 'closure_revision' => :lifecycle_policies_manage,
           'lifecycle' => :lifecycle_policies_manage, 'operational' => :queues_manage }.freeze

  def call(unit_id:, kind:, code:, payload:, expected_version:)
    capability = CAPS.fetch(kind) { raise ArgumentError }
    raise ArgumentError unless payload.is_a?(Hash) && payload.to_json.bytesize <= 100_000

    with_unit(unit_id, administrative: true) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(capability)

      row = JrcServiceDesk::AutomationDraft.where(account: context.account, unit: unit, account_user: context.account_user).find_or_initialize_by(
        kind: kind, code: code
      )
      raise ActiveRecord::StaleObjectError.new(row, 'update') unless expected_version.to_s == (row.persisted? ? row.lock_version.to_s : '-1')

      row.payload = payload
      row.save!
      row
    end
  end
end
