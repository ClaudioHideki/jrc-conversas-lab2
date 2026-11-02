class JrcHumanAssignmentPolicyEvent < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :user, optional: true
  validates :inbox, presence: true, on: :create, unless: -> { next_policy.to_h.stringify_keys['scope'] == 'GLOBAL_ACCOUNT' }

  def readonly?
    super || persisted?
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, 'Human assignment policy history is append-only' if persisted?

    super
  end
end
