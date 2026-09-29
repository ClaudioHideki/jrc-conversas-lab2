module JrcOperations
  class Access
    def self.ready?
      ActiveRecord::Base.connection.data_source_exists?('jrc_projects_projects')
    end
    def self.refresh(member)
      return unless member&.persisted?
      AccountUser.find_by(id: member.id, account_id: member.account_id, user_id: member.user_id)
    end
    def self.enabled?(account, kind)
      flag = { 'projects' => 'jrc_projects', 'service_desk' => 'jrc_service_desk' }.fetch(kind)
      account.reload.active? && account.feature_enabled?(flag)
    end
    def self.admin?(member)
      member = refresh(member)
      member && member.administrator? && member.custom_role_id.nil?
    end
    def self.project_access?(member)
      member = refresh(member)
      member && enabled?(member.account, 'projects') && (admin?(member) || member.jrc_projects_enabled?)
    end
    def self.project_creator?(member)
      JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.project.create')
    end
    def self.r2_context(member)
      member = refresh(member)
      return {} unless member
      { account: member.account, user: member.user, account_user: member }
    end
    def self.user_context(account_user)
      { user: account_user.user, account: account_user.account, account_user: account_user }
    end
    def self.tickets(member)
      JrcServiceDesk::TicketPolicy::Scope.new(r2_context(member), JrcServiceDesk::Ticket).resolve
    end
    def self.projects(account_user)
      scope = JrcProjects::Project.where(account_id: account_user&.account_id)
      return scope.none unless project_access?(account_user)
      return scope.none unless JrcProjects::Authorization.allowed?(account_user: account_user, capability: 'projects.project.view')
      return scope if admin?(account_user)
      member_ids = JrcProjects::ProjectMember.where(account_id: account_user.account_id, user_id: account_user.user_id).select(:project_id)
      scope.where(owner_id: account_user.user_id).or(scope.where(id: member_ids)).or(scope.where(visibility: 'account'))
    end
    def self.conversation!(account_user, display_id)
      record = account_user.account.conversations.find_by!(display_id: display_id)
      raise Pundit::NotAuthorizedError unless ConversationPolicy.new(user_context(account_user), record).show?
      record
    end
    def self.contact!(account_user, id)
      record = account_user.account.contacts.find(id)
      raise Pundit::NotAuthorizedError unless ContactPolicy.new(user_context(account_user), record).show?
      record
    end
    def self.crm?(account_user)
      account_user && account_user.account.feature_enabled?('jrc_crm') && account_user.permissions.include?('jrc_crm')
    end
    def self.ticket!(account_user, id, write: false, lock: false)
      scope = tickets(account_user)
      record = (lock ? scope.lock : scope).find(id)
      policy = JrcServiceDesk::TicketPolicy.new(r2_context(account_user), record)
      raise Pundit::NotAuthorizedError unless write ? policy.update? : policy.show?
      record
    end
    def self.deal_context!(record)
      account = record.account
      account.contacts.find(record.contact_id) if record.contact_id.present?
      account.jrc_crm_organizations.find(record.organization_id) if record.organization_id.present?
      if record.company_id.present?
        raise ActiveRecord::RecordNotFound unless defined?(::Company) && account.respond_to?(:companies)
        account.companies.find(record.company_id)
      end
      record
    end
    def self.deal!(account_user, id, won: false, write: false, lock: false)
      raise Pundit::NotAuthorizedError unless crm?(account_user)
      scope = JrcCrm::Deal.where(account_id: account_user.account_id)
      scope = scope.where(owner_id: account_user.user_id) unless admin?(account_user)
      record = (lock ? scope.lock : scope).find(id)
      policy = JrcCrm::DealPolicy.new(user_context(account_user), record)
      raise Pundit::NotAuthorizedError unless (write ? policy.update? : policy.show?)
      raise ArgumentError, 'Confirme a venda no CRM antes de criar ou vincular a entrega.' if won && !record.won?
      deal_context!(record)
    end
  end
end
