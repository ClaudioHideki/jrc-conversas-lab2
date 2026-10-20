class Api::V1::Accounts::JrcBrokerController < Api::V1::Accounts::BaseController
  wrap_parameters false
  before_action :feature_enabled!
  before_action :no_store
  before_action :verify_control_csrf!
  before_action :reject_query!
  before_action :authorize_management!, except: [:status, :pair, :pair_operation, :disconnect, :confirm_identity]
  rescue_from JrcBroker::Client::Error, with: :broker_error
  rescue_from JrcBroker::Configuration::InvalidConfiguration, JrcBroker::CredentialStore::InvalidCredential, with: :configuration_error

  def show
    record = JrcBrokerIntegration.find_by(account_id: Current.account.id)
    render json: { enabled: true, configured: record.present?, has_credential: record&.encrypted_control_key.present?,
                   origin: record&.broker_origin, organizationId: record&.organization_id,
                   allowedOrigins: ENV.fetch('JRC_BROKER_ALLOWED_ORIGINS', '').split(',').map(&:strip) }
  end

  def update
    input = body!('origin', 'organizationId', 'controlKey')
    client = JrcBroker::Client.new(origin: input['origin'], token: input['controlKey'], actor_id: Current.user.id)
    JrcBroker::Configuration.configure!(account: Current.account, origin: input['origin'], organization_id: input['organizationId'],
                                        token: input['controlKey'], client: client)
    show
  end

  def resources
    data = broker.client.resources
    connections = data.fetch('connections', [])
    inbox_ids = Current.account.inboxes.where(id: connections.pluck('inboxId'), channel_type: 'Channel::Api').pluck(:id)
    render json: { providers: data.fetch('providers').map { |value| value.slice('id', 'name') },
                   connections: connections.select { |value| inbox_ids.include?(value['inboxId']) }
                                    .map { |value| value.slice('integrationId', 'inboxId', 'name') },
                   instances: data.fetch('instances').map { |value| value.slice('id', 'name', 'status') },
                   agents: Current.account.users.select(:id, :name).map { |user| { id: user.id, name: user.name } } }
  end

  def assignment_policy
    render json: JrcHumanAssignment::Policy.for(Current.account).slice(:enabled, :max_open, :inbox_ids)
  end

  def update_assignment_policy
    input = body!('enabled', 'max_open', 'inbox_ids')
    render json: JrcHumanAssignment::Policy.update!(Current.account, enabled: input['enabled'], max_open: input['max_open'],
                                                                  inbox_ids: input['inbox_ids'])
  rescue ArgumentError
    render json: { code: 'JRC_BROKER_INVALID_ASSIGNMENT_POLICY' }, status: :unprocessable_entity
  end

  def onboardings
    render json: { data: broker.client.operations.fetch('data').map { |value| JrcBroker::Response.operation(value) } }
  end

  def adopt
    input = body!('integrationId')
    render json: broker.adopt!(input['integrationId'])
  end

  def create_onboarding
    input = body!('name', 'source', 'inboxId', 'agentIds', 'replaceExistingWebhook')
    Current.account.inboxes.find(input['inboxId']) if input['inboxId']
    key = idempotency_key!
    result = broker.client.start_onboarding(input, key: key)
    render json: JrcBroker::Response.operation(result), status: :accepted
  end

  def onboarding
    result = broker.bind_completed!(broker.client.onboarding(params[:operation_id]))
    render json: JrcBroker::Response.operation(result)
  end

  def recover_onboarding
    input = body!('action')
    key = idempotency_key!
    result = broker.client.recover_onboarding(params[:operation_id], action: input['action'], key: key)
    render json: JrcBroker::Response.operation(result), status: :accepted
  end

  def status
    render json: control.status
  end

  def pair
    body!
    render json: control.pair(key: idempotency_key!)
  end

  def pair_operation
    render json: control.pair_operation(operation_id: params[:operation_id])
  end

  def disconnect
    body!
    render json: control.disconnect(key: idempotency_key!)
  end

  def confirm_identity
    input = body!('observedRevision')
    render json: control.confirm_identity(revision: input['observedRevision'], key: idempotency_key!)
  end

  def grants
    render json: { data: JrcBroker::Grants.list(account: Current.account, inbox: binding.inbox) }
  end

  def update_grants
    input = body!('userIds')
    render json: { data: JrcBroker::Grants.update!(account: Current.account, inbox: binding.inbox, user_ids: input['userIds']) }
  end

  def assign_agents
    input = body!('agentIds')
    render json: control.assign_agents(ids: input['agentIds'], key: idempotency_key!)
  end

  private

  def binding
    @binding ||= JrcBrokerInboxBinding.find_by!(account_id: Current.account.id, inbox_id: Current.account.inboxes.find(params[:inbox_id]).id)
  end

  def control
    JrcBroker::Control.new(account: Current.account, user: Current.user, account_user: Current.account_user, binding: binding)
  end

  def broker
    @broker ||= JrcBroker::Context.new(account: Current.account, user: Current.user)
  end

  def authorize_management!
    return if JrcBrokerPolicy.new(pundit_user, nil).manage?

    raise JrcBroker::Client::Error.new('JRC_BROKER_FORBIDDEN', status: 403)
  end

  def feature_enabled!
    return if JrcBroker::Configuration.enabled? && Current.account.feature_enabled?('jrc_broker')

    head :not_found
  end

  def no_store
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
  end

  def body!(*keys)
    value = request.request_parameters
    raise JrcBroker::Client::Error.new('JRC_BROKER_INVALID_REQUEST', status: 400) unless (value.keys - keys).empty?

    value.slice(*keys)
  end

  def idempotency_key!
    key = request.headers['Idempotency-Key'].to_s
    raise JrcBroker::Client::Error.new('JRC_BROKER_INVALID_REQUEST', status: 400) unless /\A[A-Za-z0-9:_-]{8,128}\z/.match?(key)

    key
  end

  def reject_query!
    raise JrcBroker::Client::Error.new('JRC_BROKER_INVALID_REQUEST', status: 400) if request.query_parameters.present?
  end

  def verify_control_csrf!
    # Existing header-based API/Devise authentication does not rely on ambient cookies.
    return if authenticate_by_access_token? || verified_header_token?
    return if request.get? || request.head? || verified_request?

    raise JrcBroker::Client::Error.new('JRC_BROKER_CSRF_REQUIRED', status: 403)
  end

  def verified_header_token?
    token = request.headers['access-token']
    token.present? && Current.user.valid_token?(token, request.headers['client'].presence || 'default')
  end

  def render_unauthorized(_message)
    render json: { code: 'JRC_BROKER_FORBIDDEN' }, status: :forbidden
  end

  def broker_error(error)
    no_store
    render json: { code: error.message }, status: error.status
  end

  def configuration_error(_error)
    no_store
    render json: { code: 'JRC_BROKER_CONFIGURATION_REQUIRED' }, status: :unprocessable_entity
  end
end
