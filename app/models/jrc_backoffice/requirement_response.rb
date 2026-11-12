class JrcBackoffice::RequirementResponse < ApplicationRecord
  self.table_name = 'jrc_backoffice_requirement_responses'
  belongs_to :account
  belongs_to :requirement_plan, class_name: 'JrcBackoffice::RequirementPlan'
  belongs_to :actor, class_name: 'User'
  validates :requirement_key, presence: true
  validates :revision, numericality: { only_integer: true, greater_than: 0 },
                         uniqueness: { scope: %i[requirement_plan_id requirement_key] }
  validates :reason, length: { minimum: 1, maximum: 4000 }
  validate :consistent_response
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Requirement answers are immutable revisions' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Requirement answers are immutable revisions' }

  private

  def consistent_response
    errors.add(:account, 'must match the plan') if requirement_plan&.account_id != account_id
    errors.add(:actor, 'must belong to this account') unless AccountUser.exists?(account_id: account_id, user_id: actor_id)
    row = requirement_plan&.entries&.find { |entry| entry['key'] == requirement_key }
    raise ArgumentError, 'Requirement is not in the captured plan' unless row

    JrcBackoffice::RequirementDefinition.response_payload!(row.fetch('definition'), payload)
  rescue ArgumentError => error
    errors.add(:payload, error.message)
  end
end
