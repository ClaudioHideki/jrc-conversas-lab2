# frozen_string_literal: true

# An immutable source/target receipt, not another task catalogue. Task content,
# ownership and state stay in the existing native Projects module.
class JrcContactCenter::RecordingTaskLink < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false
  self.filter_attributes += %i[idempotency_key request_fingerprint scope_snapshot]

  belongs_to :recording, class_name: 'TelephonyCallRecord'
  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'
  belongs_to :created_by, class_name: 'User'
  validates :project_id, :task_id, :actor_account_user_id, :idempotency_key, :request_fingerprint, :scope_snapshot, :created_at, presence: true
  validates :idempotency_key, uniqueness: { scope: :account_id }

  # Reuse the existing authorized native destination-reference projection.
  def destination_kind
    'project_task'
  end

  def operation
    'create_task'
  end

  def target_type
    'JrcProjects::Task'
  end

  def target_id
    task_id
  end
end
