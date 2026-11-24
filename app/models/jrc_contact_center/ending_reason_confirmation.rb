# frozen_string_literal: true

# Classification evidence only; neither ACW completion nor permission to mutate another module.
class JrcContactCenter::EndingReasonConfirmation < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :qualification, class_name: 'JrcContactCenter::Qualification', optional: true
  self.filter_attributes += %i[payload input_digest]

  validates :request_key, :input_digest, :reason_code, presence: true

  after_create_commit :dispatch_ending_automations

  private

  def dispatch_ending_automations
    source_id = self.class.where(account_id: account_id, id: id).pick(:source_qualification_id)
    return unless source_id

    JrcContactCenter::EndingActions::EnqueueQualification.call(account_id: account_id, qualification_id: source_id)
  end
end
