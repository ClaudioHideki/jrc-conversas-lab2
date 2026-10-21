# frozen_string_literal: true

module ContactCenterAcwGuard
  extend ActiveSupport::Concern

  included do
    validate :validate_contact_center_resolution
    validate :validate_contact_center_assignment
    validate :protect_contact_center_cycle
    before_update :advance_contact_center_cycle
  end

  private

  def contact_center_tabulation_required?
    account.feature_enabled?('jrc_contact_center') && (inbox.whatsapp? || inbox.twilio_whatsapp?)
  end

  def validate_contact_center_resolution
    return unless contact_center_tabulation_required? && will_save_change_to_status? && resolved? && persisted?

    completed = JrcContactCenter::Qualification.where(account_id: account_id, conversation_id: id,
                                                       conversation_cycle: additional_attributes.fetch('jrc_acw_cycle', 0).to_i)
                                              .where.not(completed_at: nil).exists?
    errors.add(:base, 'contact_center_tabulation_required') unless completed
  end

  def validate_contact_center_assignment
    return unless account.feature_enabled?('jrc_contact_center') && will_save_change_to_assignee_id?

    pending = JrcContactCenter::Qualification.pending.where(account_id: account_id)
    if persisted? && pending.exists?(conversation_id: id)
      errors.add(:base, 'contact_center_tabulation_pending')
    elsif assignee_id && pending.joins(:account_user).where(account_users: { user_id: assignee_id }).exists?
      errors.add(:base, 'contact_center_agent_acw')
    end
  end

  def advance_contact_center_cycle
    return unless contact_center_tabulation_required? && status_change_to_be_saved == %w[resolved open]

    self.additional_attributes = additional_attributes.merge('jrc_acw_cycle' => additional_attributes.fetch('jrc_acw_cycle', 0).to_i + 1)
  end

  def protect_contact_center_cycle
    return unless persisted? && contact_center_tabulation_required? && will_save_change_to_additional_attributes?

    prior = additional_attributes_in_database.fetch('jrc_acw_cycle', 0).to_i
    errors.add(:base, 'contact_center_cycle_is_readonly') unless additional_attributes.fetch('jrc_acw_cycle', 0).to_i == prior
  end
end
