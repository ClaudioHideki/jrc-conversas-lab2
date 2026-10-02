# Extends the existing Ticket/Project rows, not the operator-company hierarchy.
module JrcCustomers::OperationalCompanyLink
  extend ActiveSupport::Concern
  included do
    belongs_to :master_company, class_name: 'JrcCustomers::Company', foreign_key: :company_id, optional: true
    before_validation :resolve_operational_company, if: :master_operational_link_changed?
    validate :validate_operational_company_tenant, if: :master_operational_link_changed?
  end

  def master_company_candidates
    person = is_a?(JrcServiceDesk::Ticket) ? requester : contact
    candidates = []
    candidates << person.company_id if person && person.account_id == account_id
    if is_a?(JrcProjects::Project) && persisted?
      operation_links.where(account_id: account_id).includes(:ticket, :crm_deal, conversation: :contact).each do |link|
        candidates << link.ticket&.company_id
        candidates << link.crm_deal&.company_id
        candidates << link.conversation&.contact&.company_id
      end
    end
    if is_a?(JrcServiceDesk::Ticket) && persisted?
      JrcOperations::Link.where(account_id: account_id, ticket_id: id).includes(:project).each do |link|
        candidates << link.project&.company_id
      end
    end
    candidates.compact
  end

  private

  def master_operational_link_changed?
    has_attribute?(:company_id) && account&.feature_enabled?('jrc_customer_master') &&
      (new_record? || %w[company_id contact_id requester_id].any? { |key| has_attribute?(key) && will_save_change_to_attribute?(key) })
  end

  def resolve_operational_company
    candidates = master_company_candidates
    if persisted? && will_save_change_to_company_id? && company_id.nil? && candidates.any?
      errors.add(:company_id, 'cannot clear a company required by the linked contact or source')
      return
    end
    self.company_id = JrcCustomers::CompanyLinkDecision.resolve(explicit: company_id, candidates: candidates)
  rescue JrcCustomers::CompanyLinkDecision::Conflict => error
    errors.add(:company_id, error.message)
  end

  def validate_operational_company_tenant
    if company_id.present? && !JrcCustomers::Company.where(account_id: account_id, id: company_id).exists?
      errors.add(:company_id, 'must belong to this account')
    end
  end
end
