class JrcBroker::Control
  def initialize(account:, user:, account_user:, binding:, source_ip: nil)
    @account = account
    @user = user
    @account_user = account_user
    @binding = binding
    @history = JrcBroker::ConnectionHistory.new(binding, user: user, source_ip: source_ip)
  end

  def status
    authorize!(:status)
    value = remote_status
    authorize!(:status)
    @history.observe!(value)
    value['allowedActions'] = Array(value['allowedActions']).select { |action| permitted_action?(action, value) }
    value
  end

  def pair(key:)
    authorize!(:pair)
    state = remote_status
    raise JrcBroker::Client::Error.new('JRC_BROKER_FORBIDDEN', status: 403) unless permitted_action?('pair', state)

    authorize!(:pair)
    @history.request!('pair', key: key, state: state)
    result = JrcBroker::Response.mutation(context.client.pair(@binding.integration_id, key: key), @binding)
    authorize!(:pair) # Do not release a QR to an operator revoked during the remote request.
    @history.result!(result, key: key)
    result
  rescue JrcBroker::Client::Error => error
    @history.failed!(error, key: key) if state
    raise
  end

  def pair_operation(operation_id:)
    authorize!(:pair)
    result = JrcBroker::Response.pair_operation(context.client.pair_operation(@binding.integration_id, operation_id), operation_id)
    authorize!(:pair) # A revoked grant must also hide progress returned by the remote request.
    @history.result!(result) if result['action']
    result
  end

  def disconnect(key:)
    authorize!(:disconnect)
    context
    authorize!(:disconnect)
    @history.request!('disconnect', key: key)
    requested = true
    JrcBroker::Response.mutation(context.client.disconnect(@binding.integration_id, key: key), @binding)
  rescue JrcBroker::Client::Error => error
    @history.failed!(error, key: key) if requested
    raise
  end

  def confirm_identity(revision:, key:)
    authorize!(:confirm_identity)
    context
    authorize!(:confirm_identity)
    context.client.confirm_identity(@binding.integration_id, revision: revision, key: key)
    @history.identity_confirmed!(key: key)
    { ok: true }
  end

  def assign_agents(ids:, key:)
    authorize!(:manage)
    JrcBroker::Grants.validate_ids!(ids)
    raise JrcBroker::Client::Error.new('JRC_BROKER_FORBIDDEN', status: 403) if ids.empty? || (ids - @account.users.where(id: ids).pluck(:id)).any?

    context
    authorize!(:manage)
    context.client.assign_agents(@binding.integration_id, agent_ids: ids, key: key)
    { ok: true }
  end

  private

  def policy
    JrcBrokerPolicy.new({ user: @user, account: @account.reload, account_user: @account_user }, @binding)
  end

  def authorize!(action)
    return if policy.public_send("#{action}?")

    raise JrcBroker::Client::Error.new('JRC_BROKER_FORBIDDEN', status: 403)
  end

  def context
    @context ||= JrcBroker::Context.new(account: @account, user: @user)
  end

  def remote_status
    JrcBroker::Response.health(context.client.status(@binding.integration_id), @binding)
  end

  def permitted_action?(action, state)
    return false unless %w[status pair disconnect manage].include?(action) && policy.public_send("#{action}?")
    return true unless action == 'pair'
    return false unless Array(state['allowedActions']).include?('pair')
    return true if policy.manage?

    state['identityApproved'] == true && state['identityStatus'] != 'CONFIRMATION_REQUIRED'
  end
end
