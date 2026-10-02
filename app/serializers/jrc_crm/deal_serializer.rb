module JrcCrm
  class DealSerializer
    def initialize(deal)
      @deal = deal
    end

    def as_json(options = {})
      next_activity = @deal.next_activity
      primary_contact = @deal.contact || @deal.contacts.first
      conversation = latest_conversation
      {
        id: @deal.id,
        title: @deal.title,
        value_cents: @deal.value_cents,
        value_display: format_currency(@deal.value_cents, @deal.currency),
        currency: @deal.currency,
        status: @deal.status,
        probability: @deal.probability,
        weighted_value_cents: @deal.weighted_value_cents,
        pipeline: { id: @deal.pipeline_id, name: @deal.pipeline.name },
        pipeline_id: @deal.pipeline_id,
        pipeline_name: @deal.pipeline.name,
        stage: { id: @deal.stage_id, name: @deal.stage.name, color: @deal.stage.color },
        stage_id: @deal.stage_id,
        stage_name: @deal.stage.name,
        owner: { id: @deal.owner_id, name: @deal.owner.name },
        owner_id: @deal.owner_id,
        owner_name: @deal.owner.name,
        contacts: @deal.contacts.map { |c| { id: c.id, name: c.name } },
        contact_id: @deal.contact_id,
        company_id: @deal.company_id,
        company_name: @deal.account.feature_enabled?('jrc_customer_master') ? JrcCustomers::Company.where(account_id: @deal.account_id).find_by(id: @deal.company_id)&.name : nil,
        organization_id: @deal.organization_id,
        contact: serialize_contact(primary_contact),
        conversation: conversation && { id: conversation.id, display_id: conversation.display_id, inbox_id: conversation.inbox_id },
        team: @deal.team && { id: @deal.team.id, name: @deal.team.name },
        products_count: association_count(@deal.products),
        deal_products: serialize_deal_products,
        products_subtotal_cents: @deal.deal_products.sum { |item| item.unit_price_cents.to_i * item.quantity.to_i },
        products_discount_cents: @deal.deal_products.sum { |item| item.discount_cents.to_i },
        proposals_count: association_count(@deal.proposals),
        last_activity_at: @deal.last_activity_at,
        next_activity: next_activity && serialize_activity(next_activity),
        overdue: @deal.overdue?,
        expected_close_at: @deal.expected_close_at,
        expected_close_at_display: format_datetime(@deal.expected_close_at),
        won_at: @deal.won_at,
        won_at_display: format_datetime(@deal.won_at),
        lost_at: @deal.lost_at,
        lost_at_display: format_datetime(@deal.lost_at),
        lost_reason: @deal.lost_reason_id ? { id: @deal.lost_reason_id, name: @deal.lost_reason.name } : nil,
        source: @deal.source,
        custom_attributes: @deal.custom_attributes,
        created_at: @deal.created_at,
        created_at_display: format_datetime(@deal.created_at)
      }
    end

    private

    def format_currency(cents, currency)
      # simplified currency formatting
      "#{currency} #{cents / 100.0}"
    end

    def serialize_contact(contact)
      return nil unless contact

      {
        id: contact.id,
        name: contact.name.presence || contact.identifier.presence || contact.email.presence || contact.phone_number,
        identifier: contact.identifier,
        email: contact.email,
        phone_number: contact.phone_number
      }
    end

    def serialize_deal_products
      @deal.deal_products.includes(:product).map do |item|
        {
          id: item.id,
          product_id: item.product_id,
          product: item.product && { id: item.product_id, name: item.product.name, sku: item.product.sku },
          quantity: item.quantity,
          unit_price_cents: item.unit_price_cents,
          discount_cents: item.discount_cents,
          total_cents: item.total_cents,
          notes: item.notes
        }
      end
    end

    def serialize_activity(activity)
      {
        id: activity.id,
        title: activity.title,
        activity_type: activity.activity_type,
        status: activity.status,
        due_at: activity.due_at,
        due_at_display: format_datetime(activity.due_at),
        is_overdue: activity.due_at.present? && activity.due_at < Time.current
      }
    end

    def latest_conversation
      if @deal.association(:deal_conversations).loaded?
        @deal.deal_conversations.filter_map(&:conversation).max_by(&:updated_at)
      else
        @deal.conversations.order(updated_at: :desc).first
      end
    end

    def association_count(association)
      association.loaded? ? association.size : association.count
    end

    def format_datetime(value)
      return nil unless value

      I18n.l(value.in_time_zone, format: '%d/%m/%Y %H:%M')
    end
  end
end
