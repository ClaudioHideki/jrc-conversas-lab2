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
      render json: serialize(@order)
    end

    def preview
      if params.dig(:sales_order, :proposal_id).present?
        proposal = visible_to_current_user(crm_scope.jrc_crm_proposals).find(params.dig(:sales_order, :proposal_id))
        return render json: proposal.financial_summary
      end
      render json: JrcCrm::OrderFinancials.new(attributes: order_params.to_h, items: submitted_items).call
    end

    def create
      order = nil
      proposal_id = params[:proposal_id].presence || params.dig(:sales_order, :proposal_id).presence
      JrcCrm::SalesOrder.transaction do
        order = if proposal_id
                  proposal = visible_to_current_user(crm_scope.jrc_crm_proposals).find(proposal_id)
                  service = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: Current.user)
                  result = service.call
                  if service.created && params[:sales_order].present?
                    op_keys = %w[order_type activation_date cost_center financial_notes operation_owner_name
                      customer_owner_name implementation_team priority operation_notes generate_contract
                      send_to_implementation create_follow_up follow_up_due_at tags checklist documents]
                    result.update!(notes: order_params[:notes],
                      status: order_params[:status] == 'draft' ? 'draft' : 'pending',
                      snapshot: result.snapshot.merge(order_snapshot.to_h.slice(*op_keys)))
                  end
                  result
                else
                  build_manual_order
                end
        sync_downstream!(order)
      end
      render json: serialize(order.reload), status: :created
    end

    def update
      @order.with_lock do
        attrs = order_params.to_h
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

    def build_manual_order
      attrs = order_params.to_h
      validate_order_links!(attrs)
      owner_id = attrs.delete('owner_id')
      owner = owner_id.present? ? crm_scope.users.find(owner_id) : Current.user
      snapshot = order_snapshot.to_h.except('financials', 'financial_version', 'document_brand')
      snapshot['company_name'] = 'JRC Conversas' if snapshot['company_name'].blank?
      result = JrcCrm::OrderFinancials.new(attributes: attrs.merge('snapshot' => snapshot), items: submitted_items).call
      order = crm_scope.jrc_crm_sales_orders.create!(
        attrs.except(*JrcCrm::OrderFinancials::STORED_FIELDS.map(&:to_s)).merge(
          JrcCrm::OrderFinancials.attributes_for(result)
        ).merge(owner: owner, source_type: 'manual', snapshot: JrcCrm::OrderFinancials.snapshot_for(result, snapshot))
      )
      result[:items].each { |item| order.order_items.create!(item) }
      order
    end

    def validate_order_links!(attrs)
      visible_to_current_user(crm_scope.jrc_crm_deals).find(attrs['deal_id']) if attrs['deal_id'].present?
      authorize crm_scope.contacts.find(attrs['contact_id']), :show? if attrs['contact_id'].present?
      if attrs['owner_id'].present? && attrs['owner_id'].to_i != Current.user.id && !crm_admin?
        raise Pundit::NotAuthorizedError
      end
    end

    def set_order
      @order = visible_to_current_user(crm_scope.jrc_crm_sales_orders).find(params[:id])
    end

    def order_params
      params.require(:sales_order).permit(
        :deal_id, :proposal_id, :contact_id, :owner_id, :business_unit_id, :status,
        :products_cents, :shipping_cents, :discount_cents, :total_cents, :monthly_cents,
        :payment_condition, :payment_method, :down_payment_cents, :installments_count,
        :sold_at, :closed_at, :notes,
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
        total_cents: order.total_cents, products_cents: order.products_cents,
        shipping_cents: order.shipping_cents, discount_cents: order.discount_cents,
        monthly_cents: order.monthly_cents, payment_condition: order.payment_condition,
        payment_method: order.payment_method, down_payment_cents: order.down_payment_cents,
        installments_count: order.installments_count, sold_at: order.sold_at,
        notes: order.notes, snapshot: snap, financials: order.financial_summary.except(:items),
        contact: order.contact && { id: order.contact.id, name: order.contact.name, email: order.contact.email, phone_number: order.contact.phone_number },
        owner: { id: order.owner.id, name: order.owner.name },
        business_unit: order.business_unit && { id: order.business_unit.id, name: order.business_unit.name, code: order.business_unit.code },
        deal: order.deal && { id: order.deal.id, title: order.deal.title },
        proposal: order.proposal && { id: order.proposal.id, proposal_number: order.proposal.proposal_number },
        items: order.order_items.map { |i| { id: i.id, product_id: i.product_id, name: i.name, quantity: i.quantity, unit_cents: i.unit_cents, discount_cents: i.discount_cents, one_time_cents: i.one_time_cents, recurring_cents: i.recurring_cents, snapshot: i.snapshot } },
        attachments: attachment_rows(order),
        created_at: order.created_at, updated_at: order.updated_at
      }
    end
  end
end
