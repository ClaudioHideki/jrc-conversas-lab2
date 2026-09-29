module JrcCrm
  class LeadPolicy < CrmPolicy
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
      update?
    end

    def convert?
      same_account? && (admin? || owns_record? || @record.owner_id.nil?)
    end

    def lose?
      convert?
    end
  end
end
