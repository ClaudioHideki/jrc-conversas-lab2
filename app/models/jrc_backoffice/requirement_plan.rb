class JrcBackoffice::RequirementPlan < ApplicationRecord
  self.table_name = 'jrc_backoffice_requirement_plans'
  belongs_to :account
  belongs_to :backoffice_request, class_name: 'JrcCrm::BackofficeRequest'
  belongs_to :created_by, class_name: 'User'
  has_many :responses, class_name: 'JrcBackoffice::RequirementResponse', dependent: :restrict_with_exception
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :backoffice_request_id }
  validates :digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :reason, length: { minimum: 1, maximum: 4000 }
  validate :valid_snapshot
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Requirement plans are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Requirement plans are immutable' }

  private

  def valid_snapshot
    errors.add(:account, 'must match the request') if backoffice_request&.account_id != account_id
    valid = entries.is_a?(Array) && entries.size <= 100 && entries.all? { |row| row.is_a?(Hash) && row['key'].is_a?(String) } &&
      entries.map { |row| row.fetch('key') }.uniq.size == entries.size
    errors.add(:entries, 'must contain at most 100 distinct requirements') unless valid
    return unless valid

    errors.add(:created_by, 'must belong to this account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
    entries.each do |row|
      JrcBackoffice::RequirementDefinition.normalize(row.fetch('definition'))
      rule = JrcBackoffice::RequirementRule.find_by(id: row['rule_id'], account_id: account_id,
        rule_key: row['key'], version: row['rule_version'])
      unless rule && rule.definition == row['definition'] && row['scope'] == { 'customer_kind' => rule.customer_kind }
        errors.add(:entries, 'must match an exact native rule revision')
      end
    end
    errors.add(:digest, 'must match the captured plan') unless digest == JrcBackoffice::RequirementDefinition.digest({ 'entries' => entries, 'source_facts' => source_facts })
  rescue KeyError, TypeError, ArgumentError => error
    errors.add(:entries, error.message)
  end
end
