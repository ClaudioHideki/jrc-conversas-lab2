module Api::V1::Accounts::Crm
  class PaymentsController < BaseController
    def index
      scope = crm_scope.jrc_crm_payments.includes(invoice: :sales_order).order(paid_at: :desc)
      scope = scope.joins(invoice: :sales_order).where(jrc_crm_sales_orders: { owner_id: Current.user.id }) unless crm_admin?
      render json: scope.map { |payment| serialize(payment) }
    end

    def create
      attributes = payment_params.to_h
      invoice = crm_scope.jrc_crm_invoices.includes(:sales_order).find(attributes.delete('invoice_id'))
      unless crm_admin? || invoice.sales_order&.owner_id == Current.user.id
        raise ActiveRecord::RecordNotFound
      end
      payment = nil
      # Same lock order as order synchronization: order, then invoice.
      JrcCrm::Payment.transaction do
        invoice.sales_order&.lock!
        invoice.lock!
        raise ActionController::BadRequest, 'Fatura cancelada nao pode receber pagamento.' if invoice.canceled?
        payment = crm_scope.jrc_crm_payments.create!(
          attributes.merge(invoice: invoice, business_unit: invoice.business_unit)
        )
        invoice.recalculate_balance!
        if invoice.reload.paid? && invoice.sales_order
          JrcCrm::OrderWorkflowSyncService.new(
            order: invoice.sales_order, actor: Current.user, event: 'payment_received'
          ).call
        end
      end
      render json: serialize(payment), status: :created
    end

    private

    def payment_params
      params.require(:payment).permit(
        :invoice_id, :amount_cents, :paid_at, :method, :external_id, :reconciliation_status,
        :interest_cents, :penalty_cents, :discount_cents, metadata: {}
      )
    end

    def serialize(payment)
      {
        id: payment.id, amount_cents: payment.amount_cents, paid_at: payment.paid_at,
        method: payment.method, external_id: payment.external_id,
        reconciliation_status: payment.reconciliation_status,
        invoice: { id: payment.invoice.id, invoice_number: payment.invoice.invoice_number },
        created_at: payment.created_at
      }
    end
  end
end
