# frozen_string_literal: true

class JrcServiceDesk::TicketTask < JrcServiceDesk::TicketRecord
  CHECKLIST_BOOLEAN_VALUES = [true, false].freeze
  STATUSES = %w[open in_progress completed cancelled].freeze

  belongs_to :created_by_membership, class_name: 'JrcServiceDesk::UnitMembership'
  belongs_to :assignee_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :audience_team, class_name: '::Team', optional: true
  belongs_to :parent_task, class_name: 'JrcServiceDesk::TicketTask', optional: true
  has_many :subtasks, class_name: 'JrcServiceDesk::TicketTask', foreign_key: :parent_task_id, dependent: :restrict_with_error, inverse_of: :parent_task
  validates :title, presence: true, length: { maximum: 255 }
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: %w[low normal high urgent] }
  validates :visibility, inclusion: { in: JrcServiceDesk::InteractionVisibility::VALUES }
  validates :idempotency_key, presence: true, uniqueness: { scope: %i[account_id unit_id ticket_id created_by_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validate :references_are_consistent
  validate :checklist_is_explicit
  validate :published_audience_is_stable, on: :update
  validate :parent_and_progression_are_consistent

  private

  def references_are_consistent
    %i[created_by_membership assignee_membership].each { |key| validate_unit_reference(key) }
    validate_account_reference(:audience_team)
    JrcServiceDesk::InteractionVisibility.attributes('visibility' => visibility, 'audience_team_id' => audience_team_id)
  rescue ArgumentError
    errors.add(:visibility, 'requires an explicit audience')
  end

  def checklist_is_explicit
    errors.add(:checklist, 'must contain titled boolean items') unless valid_checklist?
    errors.add(:checklist, 'must be complete before completion') if status == 'completed' && incomplete_checklist?
  end

  def valid_checklist?
    checklist.is_a?(Array) && checklist.size <= 100 && checklist.all? { |item| valid_checklist_item?(item) }
  end

  def valid_checklist_item?(item)
    item.is_a?(Hash) && item.keys.sort == %w[done title] && item['title'].is_a?(String) &&
      item['title'].strip.size.between?(1, 500) && CHECKLIST_BOOLEAN_VALUES.include?(item['done'])
  end

  def incomplete_checklist?
    checklist.is_a?(Array) && checklist.any? { |item| !item.is_a?(Hash) || item['done'] != true }
  end

  def published_audience_is_stable
    %w[visibility audience_team_id title description created_by_membership_id idempotency_key request_fingerprint parent_task_id completion_policy completion_policy_digest].each do |key|
      errors.add(key, 'is immutable; create a new explicit publication') if will_save_change_to_attribute?(key)
    end
  end

  def parent_and_progression_are_consistent
    validate_unit_reference(:parent_task)
    if parent_task
      errors.add(:parent_task, 'must belong to this ticket and remain open') unless parent_task.ticket_id == ticket_id &&
        parent_task.id != id && %w[open in_progress].include?(parent_task.status)
    end
    if status == 'completed' && subtasks.where.not(status: %w[completed cancelled]).exists?
      errors.add(:status, 'requires all subtasks to be complete')
    end
    policy = JrcServiceDesk::TaskCompletionPolicy.new(completion_policy)
    expected = policy.definition.empty? ? nil : JrcServiceDesk::CanonicalJson.digest(policy.definition)
    errors.add(:completion_policy_digest, 'must match the immutable policy') unless completion_policy_digest == expected
  rescue ArgumentError
    errors.add(:completion_policy, 'must use an explicit supported policy')
  end
end
