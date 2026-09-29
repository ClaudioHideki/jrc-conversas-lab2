module JrcCrm
  class ActivitySerializer
    def initialize(activity)
      @activity = activity
    end

    def as_json(options = {})
      {
        id: @activity.id,
        activity_type: @activity.activity_type,
        title: @activity.title,
        description: @activity.description,
        status: @activity.status,
        due_at: @activity.due_at,
        due_at_display: format_datetime(@activity.due_at),
        completed_at: @activity.completed_at,
        completed_at_display: format_datetime(@activity.completed_at),
        user: @activity.user_id ? { id: @activity.user_id, name: @activity.user.name } : nil,
        deal_id: @activity.deal_id,
        deal: serialize_deal,
        lead_id: @activity.lead_id,
        lead: serialize_lead,
        contact: serialize_contact,
        related_type: related_type,
        related_id: @activity.deal_id || @activity.lead_id,
        related_label: related_label,
        overdue: @activity.overdue?,
        created_at: @activity.created_at,
        created_at_display: format_datetime(@activity.created_at),
        updated_at: @activity.updated_at,
        updated_at_display: format_datetime(@activity.updated_at)
      }
    end

    private

    def serialize_contact
      contact = @activity.contact || @activity.deal&.contact || @activity.lead&.contact
      return nil unless contact

      { id: contact.id, name: contact.name, phone_number: contact.phone_number, email: contact.email }
    end

    def serialize_deal
      return nil unless @activity.deal

      { id: @activity.deal_id, title: @activity.deal.title }
    end

    def serialize_lead
      return nil unless @activity.lead

      { id: @activity.lead_id, name: @activity.lead.name }
    end

    def related_label
      return prefixed_label('Negócio', @activity.deal.title) if @activity.deal
      return prefixed_label('Lead', @activity.lead.name) if @activity.lead

      'Sem vínculo'
    end

    def related_type
      return 'deal' if @activity.deal_id
      return 'lead' if @activity.lead_id

      nil
    end

    def prefixed_label(prefix, value)
      label = value.presence || "##{@activity.deal_id || @activity.lead_id}"
      label.start_with?("#{prefix} -") ? label : "#{prefix} - #{label}"
    end

    def format_datetime(value)
      return nil unless value

      I18n.l(value.in_time_zone, format: '%d/%m/%Y %H:%M')
    end
  end
end
