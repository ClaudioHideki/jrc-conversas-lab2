module JrcOperations
  class Link < ::ApplicationRecord
    include AccountScopedRecord
    self.table_name = 'jrc_operations_links'
    belongs_to :account
    belongs_to :created_by, class_name: 'User'
    belongs_to :ticket, class_name: 'JrcServiceDesk::Ticket', optional: true
    belongs_to :project, class_name: 'JrcProjects::Project'
    belongs_to :task, class_name: 'JrcProjects::Task', optional: true
    belongs_to :conversation, optional: true
    belongs_to :crm_deal, class_name: 'JrcCrm::Deal', optional: true
    before_validation :derive_ticket_unit
    validate :valid_link_shape
    validate :consistent_customer
    validate :crm_customer_context
    validate :consistent_master_company
    private
    def derive_ticket_unit
      self.ticket_unit_id = ticket&.unit_id
    end
    def consistent_customer
      customers = [project&.contact, ticket&.requester, conversation&.contact, crm_deal&.contact].compact
      errors.add(:base, 'Cliente de outra conta.') if customers.any? { |customer| customer.account_id != account_id }
      ids = customers.map(&:id)
      if project
        project.operation_links.where(account_id: account_id).where.not(id: id).includes(:ticket, :conversation, :crm_deal).each do |link|
          ids.concat([link.ticket&.requester_id, link.conversation&.contact_id, link.crm_deal&.contact_id].compact)
        end
      end
      ids.uniq!
      errors.add(:base, 'Os registros vinculados devem pertencer ao mesmo cliente.') if ids.length > 1
    end
    def consistent_master_company
      return unless account&.feature_enabled?('jrc_customer_master')

      candidates = [project&.company_id, ticket&.company_id, crm_deal&.company_id, conversation&.contact&.company_id]
      JrcCustomers::CompanyLinkDecision.resolve(candidates: candidates)
    rescue JrcCustomers::CompanyLinkDecision::Conflict => error
      errors.add(:base, error.message)
    end

    def crm_customer_context
      Access.deal_context!(crm_deal) if crm_deal
    rescue ActiveRecord::RecordNotFound
      errors.add(:crm_deal, 'possui cliente ou empresa fora do contexto da conta')
    end
    def valid_link_shape
      targets = [ticket_id, conversation_id, crm_deal_id].compact.length
      valid = project_id.present? && targets == 1
      errors.add(:base, 'Vinculo invalido.') unless valid
      errors.add(:task, 'deve pertencer ao projeto e estar vinculada a um chamado') if task && (!ticket_id || task.project_id != project_id)
    end
  end
end
