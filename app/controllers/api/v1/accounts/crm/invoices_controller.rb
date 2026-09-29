module Api::V1::Accounts::Crm
  class InvoicesController < BaseController
    before_action :set_invoice, only: %i[show update]

    def index
      invoices = crm_scope.jrc_crm_invoices.includes(:sales_order, :contract, :contact, :payments).order(created_at: :desc)
      invoices = invoices.joins(:sales_order).where(jrc_crm_sales_orders: { owner_id: Current.user.id }) unless crm_admin?
      render json: invoices.map { |invoice| serialize(invoice) }
    end

    def show
      render json: serialize(@invoice)
    end

    def create
      attributes = invoice_params.to_h
      order = visible_to_current_user(crm_scope.jrc_crm_sales_orders).find(attributes.delete('sales_order_id'))
      contract_id = attributes.delete('contract_id')
      contract = contract_id.present? ? order.contracts.find(contract_id) : order.contracts.order(created_at: :desc).first
      subtotal = attributes['subtotal_cents'].presence&.to_i || order.total_cents
      discount = attributes['discount_cents'].to_i
      tax = attributes['tax_cents'].to_i
      total = [subtotal - discount + tax, 0].max
      invoice = crm_scope.jrc_crm_invoices.create!(
        attributes.merge(sales_order: order, contract: contract, contact: order.contact,
                         business_unit: order.business_unit, subtotal_cents: subtotal,
                         total_cents: total, balance_cents: total)
      )
      order.update!(status: 'invoiced') unless order.invoiced? || order.shipped? || order.completed?
      JrcCrm::OrderWorkflowSyncService.new(order: order, actor: Current.user).call
      render json: serialize(invoice.reload), status: :created
    end

    def update
      @invoice.update!(invoice_params.except(:sales_order_id, :contract_id, :subtotal_cents, :total_cents, :balance_cents))
      render json: serialize(@invoice.reload)
    end

    private

    def set_invoice
      scope = crm_scope.jrc_crm_invoices
      scope = scope.joins(:sales_order).where(jrc_crm_sales_orders: { owner_id: Current.user.id }) unless crm_admin?
      @invoice = scope.includes(:sales_order, :contract, :contact, :payments).find(params[:id])
    end

    def invoice_params
      params.require(:invoice).permit(
        :sales_order_id, :contract_id, :status, :competence_on, :issued_on, :due_on,
        :subtotal_cents, :discount_cents, :tax_cents, :payment_method, snapshot: {}
      )
    end

    def serialize(invoice)
      {
        id: invoice.id, invoice_number: invoice.invoice_number, status: invoice.status,
        competence_on: invoice.competence_on, issued_on: invoice.issued_on, due_on: invoice.due_on,
        subtotal_cents: invoice.subtotal_cents, discount_cents: invoice.discount_cents,
        tax_cents: invoice.tax_cents, total_cents: invoice.total_cents, balance_cents: invoice.balance_cents,
        payment_method: invoice.payment_method,
        order: invoice.sales_order && { id: invoice.sales_order.id, order_number: invoice.sales_order.order_number },
        contract: invoice.contract && { id: invoice.contract.id, contract_number: invoice.contract.contract_number },
        contact: invoice.contact && { id: invoice.contact.id, name: invoice.contact.name },
        payments: invoice.payments.order(paid_at: :desc).map do |payment|
          { id: payment.id, amount_cents: payment.amount_cents, paid_at: payment.paid_at,
            method: payment.method, reconciliation_status: payment.reconciliation_status }
        end,
        created_at: invoice.created_at, updated_at: invoice.updated_at
      }
    end
  end
end
