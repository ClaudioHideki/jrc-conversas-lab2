module JrcCrm
  class LeadSerializer
    def initialize(lead)
      @lead = lead
    end

    def as_json(options = {})
      {
        id: @lead.id,
        name: @lead.name,
        company_name: master_company&.name || @lead.company_name,
        legacy_company_name: @lead.company_name,
        email: @lead.email,
        phone: @lead.phone,
        source: @lead.source,
        status: @lead.public_status,
        score: @lead.score,
        owner: @lead.owner_id ? { id: @lead.owner_id, name: @lead.owner.name } : nil,
        team: @lead.team_id ? { id: @lead.team_id, name: @lead.team.name } : nil,
        contact_id: @lead.contact_id,
        company_id: @lead.has_attribute?(:company_id) ? @lead.company_id : nil,
        conversation_id: @lead.conversation_id,
        conversation: serialize_conversation,
        classified_at: @lead.classified_at,
        deal_id: @lead.deal&.id,
        notes: @lead.notes,
        temperature: @lead.temperature,
        custom_attributes: @lead.custom_attributes || {},
        created_at: @lead.created_at,
        updated_at: @lead.updated_at,
        history: serialize_history,
        activities_count: @lead.activities.count
      }
    end

    private

    def master_company
      return nil unless @lead.account.feature_enabled?('jrc_customer_master') && @lead.has_attribute?(:company_id)
      @master_company ||= JrcCustomers::Company.where(account_id: @lead.account_id).find_by(id: @lead.company_id)
    end

    def serialize_conversation
      return nil unless @lead.conversation

      {
        id: @lead.conversation.id,
        display_id: @lead.conversation.display_id,
        inbox_id: @lead.conversation.inbox_id
      }
    end

    def serialize_history
      JrcCrm::AuditEvent.where(account_id: @lead.account_id).for_resource(@lead.class.name, @lead.id).recent.limit(50).map do |event|
        JrcCrm::AuditEventSerializer.new(event).as_json
      end
    end
  end
end
