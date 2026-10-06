class JrcRelationship::Action < JrcRelationship::Record
  ACTIVE_STATUSES = %w[open in_progress waiting_customer].freeze
  self.table_name = 'jrc_relationship_actions'
  belongs_to :operations_queue, class_name: 'JrcOperations::Queue', optional: true
  belongs_to :operations_sla_policy, class_name: 'JrcOperations::SlaPolicy', optional: true
  after_update :sync_sla_pause, if: :saved_change_to_status?
  after_create_commit :notify_critical_action
  validate { errors.add(:operations_sla_policy, 'must use relationship scope') if operations_sla_policy && operations_sla_policy.scope_kind != 'relationship' }
  belongs_to :activity, class_name: 'JrcCrm::Activity', optional: true
  belongs_to :completed_by, class_name: 'User', optional: true
  validates :kind, :reason, :source_key, presence: true
  validates :status, inclusion: { in: %w[open in_progress waiting_customer completed dismissed] }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :result, :completed_at, :completed_by, presence: true, if: -> { status == 'completed' }

  def push_event_data
    { id: id, assignment_id: assignment_id, account_id: account_id, reason: reason, priority: priority,
      meta: { assignee: owner && { name: owner.name, thumbnail: nil } } }
  end

  private

  def notify_critical_action
    JrcRelationship::Notifications.call(self) if priority >= 80 || kind == 'retention'
  end

  def sync_sla_pause
    from, to = saved_change_to_status
    JrcOperations::SlaClock.new(self).status_changed!(from: from, to: to)
  end
end
