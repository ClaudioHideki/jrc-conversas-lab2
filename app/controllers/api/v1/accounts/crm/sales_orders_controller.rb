module Api::V1::Accounts::Crm
  class SalesOrdersController < BaseController
    before_action :set_order, only: [:show, :update, :pdf, :upload_attachments, :download_attachment]

    def index
      orders = visible_to_current_user(crm_scope.jrc_crm_sales_orders)
               .includes(:contact, :owner, :deal, :proposal, :order_items, :business_unit)
               .order(created_at: :desc)
      render json: orders.map { |order| serialize(order) }
    end

    def show
      company = serialize_selection_contact(@order.contact)
      render json: serialize(@order).merge(
        company: company && { id: company[:company_id], name: company[:company_name], tax_id: company[:tax_id] },
        allowed_statuses: allowed_order_statuses(@order),
        history: JrcCrm::AuditEvent.where(account_id: crm_scope.id, resource_type: 'JrcCrm::SalesOrder', resource_id: @order.id)
          .order(created_at: :desc, id: :desc).limit(100).map { |event| { id: event.id, event_type: event.event_type, created_at: event.created_at, metadata: event.metadata } }
      )
    end

    def preview
      if params.dig(:sales_order, :proposal_id).present?
        proposal = visible_to_current_user(crm_scope.jrc_crm_proposals).find(params.dig(:sales_order, :proposal_id))
        return render json: proposal.financial_summary
      end
      render json: JrcCrm::OrderFinancials.new(attributes: order_params.to_h, items: submitted_items).call
    end

    def selection_options
      context = selection_context
      proposal_options = selection_proposals(context[:deal])
      render json: {
        contacts: selection_contacts,
        selected_contact: serialize_selection_contact(context[:contact]),
        deals: selection_deals(context[:contact], context[:deal]),
        selected_deal: serialize_selection_deal(context[:deal]),
        proposals: proposal_options[:eligible],
        selected_proposal: context[:proposal] && JrcCrm::ProposalSerializer.new(context[:proposal]).as_json,
        proposal_state: proposal_options[:state]
      }
    end

    def create
      order = nil
      proposal_id = params[:proposal_id].presence || params.dig(:sales_order, :proposal_id).presence
      JrcCrm::SalesOrder.transaction do
        order = if proposal_id
                  proposal = visible_to_current_user(crm_scope.jrc_crm_proposals).find(proposal_id)
                  validate_proposal_request_links!(proposal)
                  service = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: Current.user)
                  result = service.call
                  if service.created && params[:sales_order].present?
                    op_keys = %w[order_type activation_date cost_center financial_notes operation_owner_name
                      customer_owner_name implementation_team priority operation_notes generate_contract
                      send_to_implementation create_implementation_project create_follow_up follow_up_due_at
                      tags checklist documents]
                    result.update!(notes: order_params[:notes],
                      status: order_params[:status] == 'draft' ? 'draft' : 'pending',
                      snapshot: result.snapshot.merge(order_snapshot.to_h.slice(*op_keys)))
                  end
                  result
                else
                  build_manual_order
                end
        sync_downstream!(order)
        audit_manual_order_created!(order) unless proposal_id
      end
      render json: serialize(order.reload), status: :created
    end

    def update
      @order.with_lock do
        before_trace = order_trace(@order)
        attrs = order_params.to_h
        if attrs['status'].present? && attrs['status'] != @order.status && !allowed_order_statuses(@order).include?(attrs['status'])
          @order.errors.add(:status, 'Transicao de status nao permitida para este pedido ou usuario.')
          raise ActiveRecord::RecordInvalid, @order
        end
        if attrs.key?('proposal_id') && attrs['proposal_id'].to_s != @order.proposal_id.to_s
          @order.errors.add(:proposal, 'O vinculo de origem nao pode ser alterado. Gere um novo pedido pela proposta.')
          raise ActiveRecord::RecordInvalid, @order
        end
        validate_order_links!(attrs)
        current = @order.financial_summary
        snapshot = (@order.snapshot || {}).deep_merge((attrs.delete('snapshot') || {}).to_h)
        submitted = params[:sales_order].key?(:items) ? submitted_items : @order.order_items.order(:id).map(&:attributes)
        proposed = JrcCrm::OrderFinancials.new(attributes: @order.attributes.merge(attrs).merge('snapshot' => snapshot), items: submitted).call
        if @order.commercial_terms_locked? && !JrcCrm::OrderFinancials.same_terms?(current, proposed)
          @order.errors.add(:base, 'Condicoes aceitas/contratadas sao imutaveis. Utilize nova proposta ou ajuste contratual explicito.')
          raise ActiveRecord::RecordInvalid, @order
        end
        @order.assign_attributes(attrs.except(*JrcCrm::OrderFinancials::STORED_FIELDS.map(&:to_s)))
        @order.assign_attributes(JrcCrm::OrderFinancials.attributes_for(proposed))
        @order.snapshot = JrcCrm::OrderFinancials.snapshot_for(proposed, snapshot)
        @order.save!
        if params[:sales_order].key?(:items)
          @order.order_items.destroy_all
          proposed[:items].each { |item| @order.order_items.create!(item) }
        end
        sync_downstream!(@order)
        audit_order!(@order, 'order_updated', { before: before_trace, after: order_trace(@order.reload) })
      end
      render json: serialize(@order.reload)
    end

    def pdf
      bytes = JrcCrm::OrderPdfService.new(@order).call
      send_data bytes, filename: "#{@order.order_number}.pdf", type: 'application/pdf', disposition: params[:download].present? ? 'attachment' : 'inline'
    end

    def upload_attachments
      uploads = Array(params[:files]).compact
      return render json: { message: 'Selecione ao menos um anexo.' }, status: :unprocessable_entity if uploads.empty?

      if @order.attachments.count + uploads.length > 10 || uploads.any? { |file| file.size > 20.megabytes }
        return render json: { message: 'Limite de 10 arquivos de ate 20 MB por pedido.' }, status: :unprocessable_entity
      end
      uploads.each { |file| @order.attachments.attach(file) }
      audit_order!(@order, 'order_attachment_uploaded', { filenames: uploads.map(&:original_filename) })
      render json: { attachments: attachment_rows(@order.reload) }, status: :created
    end

    def download_attachment
      attachment = @order.attachments.find(params[:attachment_id])
      send_data attachment.blob.download, filename: attachment.filename.to_s, type: attachment.content_type, disposition: 'attachment'
    end

    private

    def allowed_order_statuses(order)
      next_status = { 'draft' => 'pending', 'pending' => 'approved', 'approved' => 'separating',
                      'separating' => 'invoiced', 'invoiced' => 'shipped', 'shipped' => 'completed' }[order.status]
      statuses = [next_status].compact
      statuses << 'canceled' if crm_admin? && !%w[completed canceled].include?(order.status)
      statuses
    end

    def build_manual_order
      attrs = order_params.to_h
      validate_order_links!(attrs)
      raise JrcCrm::CommercialFinancials::InvalidTerms, 'Cliente e obrigatorio para criar o pedido.' if attrs['contact_id'].blank?

      owner_id = attrs.delete('owner_id')
      owner = owner_id.present? ? crm_scope.users.find(owner_id) : Current.user
      order_origin = attrs.delete('order_origin').presence || default_order_origin(attrs)
      unless JrcCrm::SalesOrder::ORIGINS.include?(order_origin)
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'Origem do pedido invalida.'
      end
      if order_origin == 'proposal_deal' && attrs['deal_id'].blank?
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'Origem Proposta/Negocio exige um negocio vinculado.'
      end

      snapshot = order_snapshot.to_h.except('financials', 'financial_version', 'document_brand')
      snapshot['company_name'] = 'JRC Conversas' if snapshot['company_name'].blank?
      snapshot['order_origin'] = order_origin
      snapshot['created_without_proposal'] = true
      result = JrcCrm::OrderFinancials.new(attributes: attrs.merge('snapshot' => snapshot), items: submitted_items).call
      source_type = attrs['deal_id'].present? ? 'deal' : 'manual'
      order = crm_scope.jrc_crm_sales_orders.create!(
        attrs.except(*JrcCrm::OrderFinancials::STORED_FIELDS.map(&:to_s)).merge(
          JrcCrm::OrderFinancials.attributes_for(result)
        ).merge(owner: owner, created_by: Current.user, source_type: source_type, order_origin: order_origin,
                snapshot: JrcCrm::OrderFinancials.snapshot_for(result, snapshot))
      )
      result[:items].each { |item| order.order_items.create!(item) }
      order
    end

    def default_order_origin(attrs)
      return 'proposal_deal' if attrs['deal_id'].present?

      'direct_sale'
    end

    def validate_proposal_request_links!(proposal)
      requested = params[:sales_order]
      return unless requested.respond_to?(:[])

      if requested[:deal_id].present? && requested[:deal_id].to_s != proposal.deal_id.to_s
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'A proposta nao pertence ao negocio informado.'
      end
      return if requested[:contact_id].blank?

      contact = crm_scope.contacts.find(requested[:contact_id])
      unless contact_matches_deal?(contact, proposal.deal)
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'A proposta nao pertence ao cliente informado.'
      end
    end

    def validate_order_links!(attrs)
      deal_id = attrs.key?('deal_id') ? attrs['deal_id'] : @order&.deal_id
      contact_id = attrs.key?('contact_id') ? attrs['contact_id'] : @order&.contact_id
      proposal_id = attrs.key?('proposal_id') ? attrs['proposal_id'] : @order&.proposal_id

      if attrs.key?('contact_id') && contact_id.blank?
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'Cliente e obrigatorio para o pedido.'
      end

      deal = deal_id.present? ? visible_to_current_user(crm_scope.jrc_crm_deals).find(deal_id) : nil
      contact = contact_id.present? ? crm_scope.contacts.find(contact_id) : nil
      proposal = proposal_id.present? ? visible_to_current_user(crm_scope.jrc_crm_proposals).find(proposal_id) : nil
      authorize contact, :show? if contact

      if proposal
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'Somente proposta aceita pode gerar pedido.' unless proposal.accepted?
        if deal.nil? || proposal.deal_id != deal.id
          raise JrcCrm::CommercialFinancials::InvalidTerms, 'A proposta nao pertence ao negocio selecionado.'
        end
      end

      if deal && contact && !contact_matches_deal?(contact, deal)
        raise JrcCrm::CommercialFinancials::InvalidTerms, 'O negocio nao pertence ao mesmo cliente do pedido.'
      end

      if attrs['owner_id'].present? && attrs['owner_id'].to_i != Current.user.id && !crm_admin?
        raise Pundit::NotAuthorizedError
      end
    end

    def contact_matches_deal?(contact, deal)
      return true if deal.contact_id == contact.id
      return true if deal.deal_contacts.where(contact_id: contact.id).exists?

      contact.company_id.present? && deal.company_id.present? && contact.company_id == deal.company_id
    end

    def set_order
      @order = visible_to_current_user(crm_scope.jrc_crm_sales_orders).find(params[:id])
    end

    def order_params
      params.require(:sales_order).permit(
        :deal_id, :proposal_id, :contact_id, :owner_id, :business_unit_id, :status,
        :products_cents, :shipping_cents, :discount_cents, :total_cents, :monthly_cents,
        :payment_condition, :payment_method, :down_payment_cents, :installments_count,
        :sold_at, :closed_at, :notes, :order_origin,
        snapshot: {}
      )
    end

    def order_snapshot
      raw = params.dig(:sales_order, :snapshot)
      raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : (raw || {})
    end

    def submitted_items
      Array(params.dig(:sales_order, :items)).map do |item|
        item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h
      end
    end

    def sync_downstream!(order)
      JrcCrm::OrderWorkflowSyncService.new(order: order.reload, actor: Current.user).call
    end


    def selection_context
      proposal = if params[:proposal_id].present?
                   visible_to_current_user(crm_scope.jrc_crm_proposals).includes(:deal, :owner, proposal_items: :product).find(params[:proposal_id])
                 end
      deal = proposal&.deal
      deal ||= visible_to_current_user(crm_scope.jrc_crm_deals).includes(:stage, :pipeline, :owner, :contact, :contacts).find(params[:deal_id]) if params[:deal_id].present?
      contact = proposal&.customer_contact || deal&.contact || deal&.contacts&.first
      contact ||= crm_scope.contacts.find(params[:contact_id]) if params[:contact_id].present?
      { proposal: proposal, deal: deal, contact: contact }
    end

    def selection_contacts
      query = params[:customer_q].to_s.strip
      return [] if query.length < 2

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
      digits = query.gsub(/\D/, '')
      scope = crm_scope.contacts
                       .joins('LEFT JOIN companies ON companies.id = contacts.company_id AND companies.account_id = contacts.account_id')
                       .where(<<~SQL.squish, q: pattern)
                         contacts.name ILIKE :q OR contacts.email ILIKE :q OR contacts.phone_number ILIKE :q OR
                         contacts.identifier ILIKE :q OR companies.name ILIKE :q OR companies.trade_name ILIKE :q OR
                         companies.tax_id ILIKE :q OR companies.customer_code ILIKE :q
                       SQL
      if digits.present?
        digit_pattern = "%#{ActiveRecord::Base.sanitize_sql_like(digits)}%"
        scope = scope.or(
          crm_scope.contacts
                   .joins('LEFT JOIN companies ON companies.id = contacts.company_id AND companies.account_id = contacts.account_id')
                   .where("REGEXP_REPLACE(COALESCE(contacts.phone_number, ''), '[^0-9]', '', 'g') LIKE :digits OR REGEXP_REPLACE(COALESCE(companies.tax_id, ''), '[^0-9]', '', 'g') LIKE :digits", digits: digit_pattern)
        )
      end
      scope.distinct.order(Arel.sql('contacts.last_activity_at DESC NULLS LAST, contacts.id DESC')).limit(20).map { |contact| serialize_selection_contact(contact) }
    end

    def selection_deals(contact, selected_deal)
      scope = visible_to_current_user(crm_scope.jrc_crm_deals).where.not(status: 'archived')
      if contact
        linked = scope.where(contact_id: contact.id)
        linked = linked.or(scope.where(id: JrcCrm::DealContact.where(contact_id: contact.id).select(:deal_id)))
        linked = linked.or(scope.where(company_id: contact.company_id)) if contact.company_id.present?
        scope = linked
      elsif params[:deal_q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:deal_q].to_s.strip)}%"
        scope = scope.where('jrc_crm_deals.title ILIKE ?', q)
      elsif selected_deal
        scope = scope.where(id: selected_deal.id)
      else
        return []
      end
      scope.includes(:stage, :pipeline, :owner, :contact, :contacts).order(updated_at: :desc).limit(30).map { |deal| serialize_selection_deal(deal) }
    end

    def selection_proposals(deal)
      return { eligible: [], state: { message: 'Selecione um negocio para consultar propostas.', counts: {} } } unless deal

      scope = visible_to_current_user(crm_scope.jrc_crm_proposals).where(deal_id: deal.id)
      counts = scope.group(:status).count
      eligible = scope.where(status: 'accepted').includes(:owner, :deal, { events: :user }, proposal_items: :product).order(accepted_at: :desc, id: :desc).limit(20)
      waiting = counts.slice('pending_approval', 'sent', 'viewed')
      waiting_count = waiting.values.sum
      message = if eligible.exists?
                  "#{eligible.size} proposta(s) aceita(s) disponivel(is)."
                elsif waiting_count.positive?
                  "Nenhuma proposta aceita disponivel. Existem #{waiting_count} proposta(s) aguardando aprovacao/aceite."
                else
                  'Nenhuma proposta aceita disponivel para este negocio.'
                end
      attention = scope.where(status: %w[pending_approval sent viewed]).order(updated_at: :desc).first
      { eligible: eligible.map { |proposal| JrcCrm::ProposalSerializer.new(proposal).as_json },
        state: { message: message, counts: counts, attention_proposal: attention && { id: attention.id, proposal_number: attention.proposal_number, status: attention.status } } }
    end

    def serialize_selection_contact(contact)
      return nil unless contact

      company = contact.company_id.present? ? JrcCustomers::Company.where(account_id: crm_scope.id).find_by(id: contact.company_id) : nil
      { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number, identifier: contact.identifier,
        company_id: company&.id, company_name: company&.name, trade_name: company&.respond_to?(:trade_name) ? company.trade_name : nil,
        tax_id: company&.respond_to?(:tax_id) ? company.tax_id : nil, customer_code: company&.respond_to?(:customer_code) ? company.customer_code : nil }
    end

    def serialize_selection_deal(deal)
      return nil unless deal
      contact = deal.contact || deal.contacts.first
      { id: deal.id, title: deal.title, value_cents: deal.value_cents, status: deal.status,
        stage: deal.stage && { id: deal.stage_id, name: deal.stage.name }, company_id: deal.company_id,
        company_name: deal.account.feature_enabled?('jrc_customer_master') ? JrcCustomers::Company.where(account_id: deal.account_id).find_by(id: deal.company_id)&.name : nil,
        contact: serialize_selection_contact(contact), owner: deal.owner && { id: deal.owner_id, name: deal.owner.name } }
    end

    def audit_manual_order_created!(order)
      event = order.proposal_id.present? ? 'order_created' : 'order_created_without_proposal'
      audit_order!(order, event, order_trace(order).merge(exceptional_without_proposal: order.proposal_id.blank?))
    end

    def order_trace(order)
      { order_origin: order.order_origin, contact_id: order.contact_id, deal_id: order.deal_id, proposal_id: order.proposal_id,
        proposal_version: order.proposal_version, owner_id: order.owner_id, created_by_id: order.created_by_id,
        source_type: order.source_type, status: order.status, occurred_at: Time.current.iso8601 }
    end

    def attachment_rows(order)
      order.attachments.map do |attachment|
        { id: attachment.id, filename: attachment.filename.to_s, content_type: attachment.content_type,
          byte_size: attachment.byte_size, created_at: attachment.created_at }
      end
    end

    def audit_order!(order, event_type, metadata)
      JrcCrm::AuditEvent.create!(account_id: crm_scope.id, actor_type: 'User', actor_id: Current.user&.id,
        event_type: event_type, resource_type: 'JrcCrm::SalesOrder', resource_id: order.id,
        from_value: {}, to_value: {}, metadata: metadata.merge(source: 'crm_orders'))
    rescue StandardError => e
      Rails.logger.warn("JRC CRM order audit failed: #{e.message}")
    end

    def serialize(order)
      snap = order.snapshot || {}
      {
        id: order.id, order_number: order.order_number, status: order.status,
        source_type: order.source_type, order_origin: order.order_origin, proposal_version: order.proposal_version,
        total_cents: order.total_cents, products_cents: order.products_cents,
        shipping_cents: order.shipping_cents, discount_cents: order.discount_cents,
        monthly_cents: order.monthly_cents, payment_condition: order.payment_condition,
        payment_method: order.payment_method, down_payment_cents: order.down_payment_cents,
        installments_count: order.installments_count, sold_at: order.sold_at,
        notes: order.notes, snapshot: snap, financials: order.financial_summary.except(:items),
        contact: order.contact && { id: order.contact.id, name: order.contact.name, email: order.contact.email, phone_number: order.contact.phone_number },
        owner: { id: order.owner.id, name: order.owner.name },
        created_by: order.created_by && { id: order.created_by.id, name: order.created_by.name },
        business_unit: order.business_unit && { id: order.business_unit.id, name: order.business_unit.name, code: order.business_unit.code },
        deal: order.deal && { id: order.deal.id, title: order.deal.title },
        proposal: order.proposal && { id: order.proposal.id, proposal_number: order.proposal.proposal_number, version_number: order.proposal_version || order.proposal.version_number },
        items: order.order_items.map { |i| { id: i.id, product_id: i.product_id, name: i.name, quantity: i.quantity, unit_cents: i.unit_cents, discount_cents: i.discount_cents, one_time_cents: i.one_time_cents, recurring_cents: i.recurring_cents, snapshot: i.snapshot } },
        attachments: attachment_rows(order),
        created_at: order.created_at, updated_at: order.updated_at
      }
    end
  end
end
