module JrcProjects
  class AuditEvent < ApplicationRecord
    belongs_to :account
    belongs_to :actor, class_name: 'User', optional: true
    def readonly? = persisted?

    def self.record!(account:, actor:, action:, auditable:, before_data: {}, after_data: {}, correlation_id: nil)
      create!(account:, actor:, action:, auditable_type: auditable.class.name, auditable_id: auditable.id,
              before_data:, after_data:, correlation_id:, created_at: Time.current)
    end
  end
end
