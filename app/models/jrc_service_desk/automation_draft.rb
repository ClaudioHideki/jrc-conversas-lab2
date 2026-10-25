# frozen_string_literal: true

class JrcServiceDesk::AutomationDraft < JrcServiceDesk::UnitRecord
  belongs_to :account_user
  validates :kind, inclusion: { in: %w[queue notification closure_revision] }
  validates :code, format: { with: /\A[a-zA-Z0-9_.:-]{1,120}\z/ }
  validates :code, uniqueness: { scope: [:account_id, :unit_id, :account_user_id, :kind] }
  validate do
    validate_account_reference(:account_user)
    errors.add(:payload, 'must be an object of at most 100 KB') unless payload.is_a?(Hash) && payload.to_json.bytesize <= 100_000
  end
end
