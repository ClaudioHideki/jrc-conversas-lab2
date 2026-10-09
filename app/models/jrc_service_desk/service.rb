# frozen_string_literal: true

# Minimal operational service identity. Not Company/CRM product/contract master.
class JrcServiceDesk::Service < JrcServiceDesk::NamedUnitRecord
  belongs_to :default_priority, class_name: 'JrcServiceDesk::Priority', optional: true
  belongs_to :default_queue, class_name: 'JrcServiceDesk::Queue', optional: true
  belongs_to :default_category, class_name: 'JrcServiceDesk::Category', optional: true
  belongs_to :default_ticket_type, class_name: 'JrcServiceDesk::TicketType', optional: true
  belongs_to :default_assignee_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  belongs_to :portal_inbox, class_name: '::Inbox', optional: true
  belongs_to :portal_execution_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: true
  validate :catalogue_configuration
  validate :portal_configuration

  def validate_answers!(answers)
    JrcServiceDesk::CatalogueAnswers.new(form_fields).validate!(answers)
  end

  private

  def portal_configuration
    validate_account_reference(:portal_inbox)
    validate_unit_reference(:portal_execution_membership)
    return unless portal_enabled?

    configuration = JrcServiceDesk::ServicePortalConfiguration.new(self)
    unless configuration.ready?
      errors.add(:portal_enabled, 'requires an active catalogue, widget, scoped real executor and default priority')
      return
    end
    errors.add(:portal_execution_membership, 'requires current native creation, customer and channel grants') unless configuration.permitted?
  end

  def catalogue_configuration
    %i[default_priority default_queue default_category default_ticket_type default_assignee_membership].each do |key|
      validate_unit_reference(key)
      validate_active_reference(key)
    end
    fields = JrcServiceDesk::CatalogueFields.new(form_fields)
    errors.add(:form_fields, 'must define explicit supported fields') unless fields.valid?
    errors.add(:form_fields, 'contains duplicate keys') if fields.duplicate_keys?
    %i[allowed_company_ids allowed_contract_ids].each do |key|
      values = public_send(key)
      valid = values.is_a?(Array) && values.size <= 100 && values.uniq == values && values.all? { |id| id.is_a?(Integer) && id.positive? }
      errors.add(key, 'must contain unique canonical IDs') unless valid
      next unless valid

      model = key == :allowed_company_ids ? JrcCustomers::Company : JrcCrm::Contract
      errors.add(key, 'must belong to this account') unless model.where(account_id: account_id, id: values).count == values.size
    end
    errors.add(:portal_history_days, 'must be a positive number of days') if portal_history_days && !portal_history_days.positive?
    errors.add(:portal_access_until, 'requires an explicit date') if portal_access_until_before_type_cast.present? && portal_access_until.nil?
  end
end
