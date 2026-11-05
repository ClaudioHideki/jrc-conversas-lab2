class JrcHumanAssignmentPolicyEvent < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :user, optional: true
  validates :inbox, presence: true, on: :create, unless: -> { next_policy.to_h.stringify_keys['scope'] == 'GLOBAL_ACCOUNT' }

  after_create_commit :publish_visibility_change

  def readonly?
    super || persisted?
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, 'Human assignment policy history is append-only' if persisted?

    super
  end

  private

  def publish_visibility_change
    return unless inbox_id && previous_policy.slice('visibility', 'supervisor_ids') != next_policy.slice('visibility', 'supervisor_ids')

    JrcHumanAssignment::VisibilityChangedJob.perform_later(id)
  end
end
