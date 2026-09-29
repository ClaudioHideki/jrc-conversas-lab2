require 'cgi'

module JrcCrm
  class ProposalSerializer
    STATUS_LABELS = {
      'draft' => 'Rascunho',
      'pending_approval' => 'Aprovação interna',
      'sent' => 'Enviada',
      'viewed' => 'Visualizada',
      'accepted' => 'Aceita',
      'rejected' => 'Recusada',
      'canceled' => 'Cancelada'
    }.freeze

    APPROVAL_LABELS = {
      'not_required' => 'Não requerida',
      'pending' => 'Pendente',
      'approved' => 'Aprovada',
      'rejected' => 'Reprovada'
    }.freeze

    def initialize(proposal, base_url: nil)
      @proposal = proposal
      @base_url = base_url.to_s.sub(%r{/$}, '')
    end

    def as_json(options = {})
      contact = @proposal.customer_contact
      conversation = @proposal.linked_conversation
      last_sent_event = @proposal.events.where(event_type: 'sent').order(created_at: :desc).includes(:user).first
      token = @proposal.public_token

      {
        id: @proposal.id,
        proposal_number: @proposal.proposal_number,
        version_number: @proposal.version_number,
        title: @proposal.title,
        status: @proposal.status,
        status_display: STATUS_LABELS.fetch(@proposal.status, @proposal.status),
        locked: @proposal.locked_for_editing?,
        locked_at: @proposal.locked_at,
        solution_description: @proposal.solution_description,
        subtotal_cents: @proposal.subtotal_cents,
        discount_cents: @proposal.discount_cents,
        item_discount_cents: @proposal.item_discount_cents,
        total_discount_cents: @proposal.total_discount_cents,
        initial_items_cents: @proposal.initial_items_cents,
        total_cents: @proposal.total_cents,
        total_first_month_cents: @proposal.total_cents,
        implementation_cents: @proposal.implementation_cents,
        monthly_cents: @proposal.monthly_cents,
        has_monthly_fee: @proposal.has_monthly_fee,
        shipping_cents: @proposal.shipping_cents,
        shipping_mode: @proposal.shipping_mode,
        shipping_in_installments: @proposal.shipping_in_installments,
        payment_condition: @proposal.payment_condition,
        down_payment_cents: @proposal.down_payment_cents,
        installments_count: @proposal.installments_count,
        recurring_monthly_cents: @proposal.has_monthly_fee? ? @proposal.monthly_cents : 0,
        contract_total_cents: @proposal.contract_total_cents,
        payable_base_cents: @proposal.payable_base_cents,
        installment_plan_cents: @proposal.installment_plan_cents,
        financials: @proposal.financial_summary.except(:items),
        valid_until: @proposal.valid_until,
        valid_until_display: @proposal.valid_until&.strftime('%d/%m/%Y'),
        term_months: @proposal.term_months,
        commercial_notes: @proposal.commercial_notes,
        next_steps: @proposal.next_steps,
        notes: @proposal.notes,
        customer_notes: @proposal.customer_notes,
        issuer: serialize_issuer,
        payment: serialize_payment,
        approval: serialize_approval,
        follow_up: {
          enabled: @proposal.follow_up_enabled,
          days: @proposal.follow_up_days
        },
        acceptance: serialize_acceptance,
        public_token: token,
        public_path: "/jrc/propostas/#{@proposal.account_id}/#{CGI.escape(token)}",
        public_url: public_url(token),
        pdf_path: "/api/v1/accounts/#{@proposal.account_id}/crm/proposals/#{@proposal.id}/pdf",
        sent_at: @proposal.sent_at,
        sent_at_display: format_datetime(@proposal.sent_at),
        viewed_at: @proposal.viewed_at,
        viewed_at_display: format_datetime(@proposal.viewed_at),
        last_viewed_at: @proposal.last_viewed_at,
        last_viewed_at_display: format_datetime(@proposal.last_viewed_at),
        viewed_count: @proposal.viewed_count,
        accepted_at: @proposal.accepted_at,
        accepted_at_display: format_datetime(@proposal.accepted_at),
        expires_at: @proposal.expires_at,
        expires_at_display: format_datetime(@proposal.expires_at),
        last_sent_channel: @proposal.last_sent_channel,
        last_sent_message_id: @proposal.last_sent_message_id,
        last_sent_conversation_id: @proposal.last_sent_conversation_id,
        last_sent_by: last_sent_event&.user && { id: last_sent_event.user_id, name: last_sent_event.user.name },
        items: @proposal.proposal_items.map { |item| serialize_item(item) },
        items_count: association_count(@proposal.proposal_items),
        owner: @proposal.owner_id ? { id: @proposal.owner_id, name: @proposal.owner.name } : nil,
        deal_id: @proposal.deal_id,
        deal: serialize_deal,
        customer: serialize_contact(contact),
        conversation: serialize_conversation(conversation),
        created_at: @proposal.created_at,
        created_at_display: format_datetime(@proposal.created_at),
        updated_at: @proposal.updated_at,
        updated_at_display: format_datetime(@proposal.updated_at)
      }
    end

    private

    def serialize_item(item)
      {
        id: item.id,
        product_id: item.product_id,
        product: item.product && {
          id: item.product_id,
          name: item.product.name,
          sku: item.product.sku,
          product_type: item.product.product_type
        },
        name_snapshot: item.name_snapshot,
        description_snapshot: item.description_snapshot,
        quantity: item.quantity,
        unit_name: item.unit_name,
        billing_model: item.billing_model,
        unit_price_cents: item.unit_price_cents,
        setup_fee_cents: item.setup_fee_cents,
        discount_cents: item.discount_cents,
        total_cents: item.total_cents,
        recurring_total_cents: item.recurring_total_cents,
        initial_total_cents: item.initial_total_cents,
        included_quantity: item.included_quantity,
        included_unit: item.included_unit,
        overage_unit_price_cents: item.overage_unit_price_cents,
        activation_days: item.activation_days,
        validation_period_days: item.validation_period_days,
        notes: item.notes
      }
    end

    def serialize_issuer
      {
        company_name: @proposal.issuer_company_name,
        tax_id: @proposal.issuer_tax_id,
        unit: @proposal.issuer_unit
      }
    end

    def serialize_payment
      {
        method: @proposal.payment_method,
        billing_day: @proposal.billing_day,
        first_billing_days: @proposal.first_billing_days,
        taxes_included: @proposal.taxes_included,
        annual_adjustment_index: @proposal.annual_adjustment_index,
        renewal_type: @proposal.renewal_type,
        cancellation_penalty_percent: @proposal.cancellation_penalty_percent.to_f
      }
    end

    def serialize_approval
      {
        status: @proposal.approval_status,
        status_display: APPROVAL_LABELS.fetch(@proposal.approval_status, @proposal.approval_status),
        commercial: @proposal.commercial_approval_status,
        commercial_display: APPROVAL_LABELS.fetch(@proposal.commercial_approval_status, @proposal.commercial_approval_status),
        financial: @proposal.financial_approval_status,
        financial_display: APPROVAL_LABELS.fetch(@proposal.financial_approval_status, @proposal.financial_approval_status),
        technical: @proposal.technical_approval_status,
        technical_display: APPROVAL_LABELS.fetch(@proposal.technical_approval_status, @proposal.technical_approval_status)
      }
    end

    def serialize_acceptance
      {
        name: @proposal.accepted_by_name,
        document: @proposal.accepted_by_document,
        remote_ip: @proposal.accepted_from_ip,
        accepted_at: @proposal.accepted_at,
        accepted_at_display: format_datetime(@proposal.accepted_at)
      }
    end

    def serialize_deal
      return nil unless @proposal.deal

      {
        id: @proposal.deal_id,
        title: @proposal.deal.title,
        source: @proposal.deal.source,
        stage: @proposal.deal.stage && { id: @proposal.deal.stage_id, name: @proposal.deal.stage.name },
        owner: @proposal.deal.owner && { id: @proposal.deal.owner_id, name: @proposal.deal.owner.name }
      }
    end

    def serialize_contact(contact)
      return nil unless contact

      {
        id: contact.id,
        name: contact.name,
        email: contact.email,
        phone_number: contact.phone_number
      }
    end

    def serialize_conversation(conversation)
      return nil unless conversation

      {
        id: conversation.id,
        display_id: conversation.display_id,
        inbox_id: conversation.inbox_id,
        inbox_name: conversation.inbox&.name,
        channel_type: conversation.inbox&.channel_type
      }
    end

    def public_url(token)
      return nil if @base_url.blank?

      "#{@base_url}/jrc/propostas/#{@proposal.account_id}/#{CGI.escape(token)}"
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
