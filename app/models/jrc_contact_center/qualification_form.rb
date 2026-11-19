# frozen_string_literal: true

# Private response state attached to the existing native qualification, not another attendance registry.
class JrcContactCenter::QualificationForm < JrcContactCenter::ApplicationRecord
  belongs_to :qualification, class_name: 'JrcContactCenter::Qualification'
  self.filter_attributes = filter_attributes + %i[snapshot answers]

  validates :qualification_id, uniqueness: true
  validate :native_identity

  private

  def native_identity
    valid = qualification&.account_id == account_id && snapshot.is_a?(Hash) && answers.is_a?(Hash)
    errors.add(:base, 'invalid_qualification_form_context') unless valid
  end
end
