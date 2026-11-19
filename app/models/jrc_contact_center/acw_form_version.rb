# frozen_string_literal: true

# Historical actor receipts are not live authority or cascading user associations.
class JrcContactCenter::AcwFormVersion < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :acw_form_template, class_name: 'JrcContactCenter::AcwFormTemplate', inverse_of: :versions

  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true, length: { maximum: 160 }
  validates :description, length: { maximum: 1000 }
  validates :status, inclusion: { in: %w[active archived] }
  validates :request_id, :actor_account_user_id, :actor_user_id, presence: true
  validate :valid_definition

  private

  def valid_definition
    JrcContactCenter::AcwFormDefinition.new(definition).call
  rescue JrcContactCenter::AcwFormDefinition::Invalid
    errors.add(:definition, 'invalid_acw_form_definition')
  end
end
