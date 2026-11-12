# Reuse native contract editing, price snapshots, approval invalidation and
# audit. Only the entry scope changes to the assigned Backoffice request.
class Api::V1::Accounts::Crm::BackofficeContractsController < Api::V1::Accounts::Crm::ContractsController
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }
  EDITABLE_FIELDS = %w[contract_template_id content_override starts_on ends_on term_months renewal_type adjustment_index due_day
                       auto_renew renewal_notice_days renewal_term_months notes].freeze
  rescue_from ArgumentError do |error|
    render json: { message: error.message }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::ContractVersions::Changed do
    render json: { code: 'CONTRACT_SOURCE_CHANGED' }, status: :conflict
  end

  def show
    data = nil
    crm_scope.with_lock('FOR SHARE') do
      @contract = context.contract!(context.request(params[:backoffice_request_id]))
      @contract.with_lock('FOR SHARE') do
        data = serialize(@contract, include_history: true).merge(source_digest: JrcBackoffice::ContractSnapshot.digest(@contract))
        context.request(params[:backoffice_request_id])
      end
    end
    response.headers['Cache-Control'] = 'no-store'
    render json: data
  end

  def update
    crm_scope.with_lock('FOR NO KEY UPDATE') do
      operation = context.writable!(context.request(params[:backoffice_request_id]))
      @contract = context.contract!(operation)
      @contract.sales_order.with_lock('FOR NO KEY UPDATE') do
        @contract.lock!('FOR NO KEY UPDATE')
        editable!
        check_preview!

        update_contract!
        context.writable!(operation)
      end
    end
    render json: serialize(@contract.reload)
  end

  def templates
    render json: template_service.options(query: params[:q], page: params[:page])
  end

  private

  def context
    @context ||= JrcBackoffice::ContractAccess.new(account: Current.account, actor: Current.user)
  end

  def set_contract
    @contract = context.contract!(context.request(params[:backoffice_request_id]))
  end

  def contract_params
    data = params.require(:contract)
    if (data.keys - EDITABLE_FIELDS).any?
      raise ArgumentError, 'Este painel altera apenas a minuta e sua vigência; valores exigem o fluxo comercial próprio.'
    end

    data.permit(*EDITABLE_FIELDS)
  end

  def normalized_contract_params
    attributes = super
    selected = attributes[:contract_template]
    attributes[:contract_template] = template_service.select!(selected.id) if selected && selected.id != @contract.contract_template_id
    attributes
  end

  def template_service
    JrcBackoffice::ContractTemplates.new(account: Current.account, actor: Current.user, request_id: params[:backoffice_request_id])
  end

  def audit_snapshot(contract)
    super.merge(contract_template_id: contract.contract_template_id)
  end

  def check_preview!
    crm_scope.jrc_crm_contract_templates.find(@contract.contract_template_id).lock!('FOR SHARE') if @contract.contract_template_id
    raise JrcBackoffice::ContractVersions::Changed unless params[:expected_source_digest] == JrcBackoffice::ContractSnapshot.digest(@contract)
  end

  def editable!
    JrcBackoffice::Signatures::DeliveryGuard.check_editable!(@contract)
    return unless @contract.signature_status.in?(%w[sent signed])

    raise ArgumentError, 'O contrato enviado ou assinado foi preservado. Use o fluxo de revisão autorizado.'
  end
end
