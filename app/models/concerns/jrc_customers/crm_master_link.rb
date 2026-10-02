module JrcCustomers::CrmMasterLink
  extend ActiveSupport::Concern
  included do
    before_validation :resolve_master_links, if: :master_reference_change?
    before_save :persist_master_links, if: :master_reference_change?
    validate :master_reference_tenant, if: :master_reference_change?
  end

  private

  def master_reference_change?
    return false unless account&.feature_enabled?('jrc_customer_master')

    new_record? || %w[company_id contact_id organization_id deal_id lead_id].any? do |key|
      has_attribute?(key) && will_save_change_to_attribute?(key)
    end
  end

  def resolve_master_links
    # Validation is read-only. New Contacts are built, not inserted by .valid?.
    if is_a?(JrcCrm::Lead) && contact_id.blank? && contact.nil?
      self.contact = JrcCustomers::LeadContactLinker.new(account: account).call(self, persist: false)
    end
    if is_a?(JrcCrm::Activity)
      self.contact_id ||= deal&.contact_id || lead&.contact_id
    end
    inferred = []
    if has_attribute?(:organization_id) && organization_id.present?
      legacy = account.jrc_crm_organizations.find(organization_id)
      plan = JrcCustomers::LegacyCompanyMapper.new(account: account, organization: legacy).plan
      inferred << plan[:company_id]
    end
    inferred << contact.company_id if contact&.account_id == account_id
    inferred += [deal&.company_id, lead&.company_id] if is_a?(JrcCrm::Activity)
    candidates = ([company_id] + inferred).compact.uniq
    if candidates.length > 1
      errors.add(:company_id, 'conflicts with the contact or CRM organization; review the link first')
    else
      self.company_id = candidates.first
    end
  rescue JrcCustomers::LegacyCompanyMapper::Conflict, JrcCustomers::LeadContactLinker::Conflict, ActiveRecord::RecordNotFound => e
    errors.add(:base, e.message)
  end

  def persist_master_links
    # Callback runs inside save's transaction. Mapping/contact changes roll back
    # with the CRM write; no new identities are committed by dry-run validation.
    if has_attribute?(:organization_id) && organization_id.present?
      legacy = account.jrc_crm_organizations.find(organization_id)
      mapped_id = JrcCustomers::LegacyCompanyMapper.new(account: account, organization: legacy).apply!.id
      if company_id.present? && company_id != mapped_id
        raise JrcCustomers::LegacyCompanyMapper::Conflict, 'Company differs from the mapped legacy organization'
      end
      self.company_id = mapped_id
    end
    return unless contact && contact.account_id == account_id

    if contact.new_record?
      contact.company_id ||= company_id
      contact.save!
      self.contact_id = contact.id
    elsif company_id.present?
      contact.with_lock do
        if contact.company_id.present? && contact.company_id != company_id
          raise JrcCustomers::LegacyCompanyMapper::Conflict, 'Contact company changed concurrently; review the link'
        end
        if contact.company_id.nil?
          contact.update!(company_id: company_id)
          JrcCustomers::Audit.record!(account: account, actor: Current.user, resource: contact,
                                      event_type: 'customer_contact_linked', to_value: { company_id: company_id })
        end
      end
    end
  end

  def master_reference_tenant
    if has_attribute?(:company_id) && company_id.present? && !JrcCustomers::Company.where(account_id: account_id, id: company_id).exists?
      errors.add(:company_id, 'must belong to this account')
    end
    return unless has_attribute?(:organization_id) && organization_id.present?
    return if JrcCrm::Organization.where(account_id: account_id, id: organization_id).exists?

    errors.add(:organization_id, 'must belong to this account')
  end
end
