module JrcCrm
  class ProposalPolicy < CrmPolicy
    def index?
      crm_agent?
    end

    def show?
      crm_agent? && same_account? && (admin? || owns_record?)
    end

    def create?
      crm_agent?
    end

    def update?
      show?
    end

    def destroy?
      show?
    end

    def send_proposal?
      same_account? && (admin? || owns_record?)
    end

    def cancel?
      send_proposal?
    end

    def accept?
      send_proposal?
    end

    def reject?
      send_proposal?
    end
  end
end
