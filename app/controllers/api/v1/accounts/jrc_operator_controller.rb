class Api::V1::Accounts::JrcOperatorController < Api::V1::Accounts::BaseController
  around_action :operator_authorization
  rescue_from Pundit::NotAuthorizedError do
    render json: { error: { code: 'FORBIDDEN' } }, status: :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: { code: 'NOT_FOUND' } }, status: :not_found
  end
  rescue_from JrcOperator::Error do |error|
    render json: { error: { code: error.message } }, status: error.status
  end
  rescue_from ActiveRecord::RecordInvalid, ActionController::ParameterMissing do
    render json: { error: { code: 'INVALID_REQUEST' } }, status: :unprocessable_entity
  end
  def context
    enabled = operator_available?
    capabilities = enabled ? JrcOperator::Access::CAPABILITIES.select { |key| Current.account_user.permissions.include?("jrc_operator_#{key}") } : []
    render json: { enabled: enabled && capabilities.include?('read'), capabilities: capabilities }
  end

  def bindings
    render json: access.bindings.includes(:contact, :company, :business_unit).filter_map { |row|
      next unless row.valid?
      next unless ContactPolicy.new(authorization_context, row.contact).show?

      { id: row.id, contact: row.contact.name, company: row.company.name, company_id: row.company_id }
    }
  end

  def options
    binding = access.binding!(params[:binding_id])
    render json: { ddds: client(binding).rede(:ddds, { 'external_actor' => Current.user.id.to_s }).fetch('items'),
                   orders: order_options(binding), conversations: conversation_options(binding) }
  end

  def customer
    binding = access.binding!(params[:binding_id])
    data = client(binding).bemtevi('cliente', {})
    rows = data.is_a?(Array) ? data : [data]
    matches = rows.select { |row| row.is_a?(Hash) && row['cod_cliente'].to_s == binding.bemtevi_customer_id }
    raise JrcOperator::Error, 'CUSTOMER_MISMATCH' unless matches.one? && rows.one?

    render json: { id: matches.first['cod_cliente'], name: matches.first['nome'] }
  end

  def plans
    binding = access.binding!(params[:binding_id])
    data = client(binding).bemtevi('cliente/planos', {})
    raise JrcOperator::Error, 'UNSUPPORTED_PLANS_SCHEMA' unless data.is_a?(Array) &&
                                                                data.all? do |row|
                                                                  row.is_a?(Hash) && row['cod_cliente'].to_s == binding.bemtevi_customer_id
                                                                end

    render json: data.map { |row| row.slice('codplano', 'descricao', 'precocliente', 'dataativacao') }
  end

  def charges
    render json: { items: client(access.binding!(params[:binding_id])).charges, observed_at: Time.current.iso8601, complete: false }
  end

  def availability
    binding = access.binding!(params[:binding_id])
    render json: client(binding).rede(:availability, { 'ddd_id' => params.require(:ddd_id), 'external_actor' => Current.user.id.to_s })
  end

  def reserve
    binding = access.binding!(params[:binding_id], 'reserve')
    raise Pundit::NotAuthorizedError unless crm_access?

    data = params.require(:reservation).permit(:number_id, :order_ref, :purpose, :expires_at).to_h
    # The order reference is always server-generated from an authorized native order.
    order = authorized_order!(binding, data.delete('order_ref'))
    data['order_ref'] = "jrc:#{Current.account.id}:order:#{order.id}"
    render json: serialize(commands(binding).remote!('reserve', data, params.require(:key)))
  end

  def release
    binding = access.binding!(params[:binding_id], 'release')
    reservation = binding.operations.where(kind: 'reserve', state: 'confirmed').find(params.require(:operation_id))
    data = { 'reservation_id' => reservation.result.fetch('reservation_id'), 'reason' => params.require(:reason) }
    render json: serialize(commands(binding).remote!('release', data, params.require(:key)))
  end

  def operations
    render json: access.binding!(params[:binding_id]).operations.order(id: :desc).limit(50).map { |row| serialize(row) }
  end

  def reconcile
    binding = access.binding!(params[:binding_id])
    operation = binding.operations.where(kind: %w[reserve release], user_id: Current.user.id).find(params.require(:operation_id))
    access.authorize!(operation.kind)
    render json: serialize(commands(binding).remote!(operation.kind, operation.request_data, operation.key))
  end

  def prepare_boleto
    binding = access.binding!(params[:binding_id], 'prepare_boleto')
    charge_id = params.require(:charge_id).to_s
    raise JrcOperator::Error, 'INVALID_CHARGE' unless /\A[1-9]\d{0,12}\z/.match?(charge_id)

    render json: serialize(commands(binding).prepare!(charge_id, params.require(:key)))
  end

  def boleto
    binding = access.binding!(params[:binding_id], 'prepare_boleto')
    operation = binding.operations.where(kind: 'prepare_boleto', state: 'confirmed').find(params[:operation_id])
    raise JrcOperator::Error, 'BOLETO_NOT_READY' unless operation.boleto.attached?

    send_data operation.boleto.download, filename: operation.boleto.filename.to_s, type: 'application/pdf', disposition: 'attachment'
  end

  def send_boleto
    binding = access.binding!(params[:binding_id], 'send_boleto')
    render json: serialize(commands(binding).send!(params.require(:operation_id), params.require(:conversation_id), params.require(:content),
                                                   params.require(:key)))
  end

  private

  def operator_available?
    return false unless Current.user.is_a?(::User) && Current.account_user

    Current.user.active_for_authentication? && Current.account.active? && Current.account.feature_enabled?('jrc_operator') &&
      ActiveRecord::Base.connection.data_source_exists?('jrc_operator_bindings')
  end

  def authorization_context
    { account: Current.account, user: Current.user, account_user: Current.account_user }
  end

  def orders_for(binding)
    JrcCrm::SalesOrder.where(account_id: binding.account_id, business_unit_id: binding.business_unit_id, contact_id: binding.contact_id)
  end

  def order_options(binding)
    orders = crm_access? ? orders_for(binding) : JrcCrm::SalesOrder.none
    orders = orders.where(owner_id: Current.user.id) unless Current.account_user.administrator?
    orders.order(id: :desc).limit(100).map { |row| { id: row.id, name: row.order_number } }
  end

  def conversation_options(binding)
    conversations = binding.account.conversations.where(contact_id: binding.contact_id, inbox_id: binding.allowed_inbox_ids)
                           .includes(:inbox).order(id: :desc).limit(100)
    conversations.filter_map do |row|
      next unless ConversationPolicy.new(authorization_context, row).show?

      { id: row.id, name: "##{row.display_id} / #{row.inbox.name}" }
    end
  end

  def authorized_order!(binding, id)
    order = orders_for(binding).find(id)
    allowed_owner = Current.account_user.administrator? || order.owner_id == Current.user.id
    raise Pundit::NotAuthorizedError unless visible_order?(order) && allowed_owner

    order
  end

  def visible_order?(order)
    JrcCrm::OrganizationalVisibility.new(account: Current.account, user: Current.user, relation: order.class.where(id: order.id)).call.exists?
  end

  def crm_access?
    Current.account.feature_enabled?('jrc_crm') && Current.account_user.permissions.include?('jrc_crm')
  end

  def operator_authorization
    yield
  rescue Pundit::NotAuthorizedError
    render json: { error: { code: 'FORBIDDEN' } }, status: :forbidden
  rescue ActionController::ParameterMissing
    render json: { error: { code: 'INVALID_REQUEST' } }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: { code: 'NOT_FOUND' } }, status: :not_found
  end

  def access
    @access ||= JrcOperator::Access.new(account: Current.account, user: Current.user)
  end

  def client(binding)
    JrcOperator::Client.new(binding)
  end

  def commands(binding)
    JrcOperator::Commands.new(binding: binding, user: Current.user)
  end

  def serialize(operation)
    { id: operation.id, kind: operation.kind, state: operation.state, result: operation.result,
      created_at: operation.created_at, message_id: operation.message_id }
  end
end
