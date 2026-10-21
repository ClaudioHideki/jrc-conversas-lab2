# frozen_string_literal: true

class JrcContactCenter::CommandDispatcher
  def initialize(account:, actor_account_user:, adapter: nil)
    @account = account
    @actor_account_user = account.account_users.find(actor_account_user.id)
    @adapter = adapter || JrcContactCenter::Providers::JrcPabxAdapter.new(account: account)
  end

  def call(action:, parameters:, **options)
    options.assert_valid_keys(:call_session, :reason_code, :expected_state_version, :command_id)
    command = nil
    replayed = false
    attributes = command_attributes(action, parameters, options)
    @account.with_lock do
      @actor_account_user.lock!
      if %w[originate answer accept].include?(action) && JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @actor_account_user)
        raise JrcContactCenter::OperationError.new('tabulation_pending', status: :conflict)
      end
      existing = JrcContactCenter::Command.find_by(account: @account, command_id: attributes.fetch(:command_id))
      if existing
        command = replay(existing, attributes)
        replayed = true
      else
        command = JrcContactCenter::Command.create!(attributes)
      end
    end
    replayed ? command : dispatch(command)
  rescue ActiveRecord::RecordNotUnique
    raise JrcContactCenter::OperationError.new('command_id_conflict', status: :conflict)
  end

  private

  def dispatch(command)
    response = @adapter.dispatch(command)
    command.with_lock { command.update!(status: 'accepted_by_gateway', response: response.to_h) if command.status == 'requested' }
    command
  rescue JrcContactCenter::Providers::BaseAdapter::CapabilityUnavailable => e
    command.with_lock { command.update!(status: 'unknown', response: { 'error' => e.message }) if command.status == 'requested' }
    raise
  rescue StandardError
    command.with_lock { command.update!(status: 'unknown', response: { 'error' => 'gateway_result_unknown' }) if command.status == 'requested' }
    raise JrcContactCenter::OperationError.new('gateway_result_unknown', status: :service_unavailable)
  end

  def command_attributes(action, parameters, options)
    session = options[:call_session]
    JrcContactCenter::CallSession.where(account: @account).find(session.id) if session
    options.slice(:call_session, :reason_code, :expected_state_version).merge(
      account: @account, actor_account_user: @actor_account_user,
      command_id: options.fetch(:command_id) { SecureRandom.uuid }, action: action,
      parameters: parameters.to_h, requested_at: Time.current
    )
  end

  def replay(command, attributes)
    keys = %w[actor_account_user_id action call_session_id reason_code expected_state_version parameters]
    expected = JrcContactCenter::Command.new(attributes)
    matches = command.attributes.slice(*keys) == expected.attributes.slice(*keys)
    raise JrcContactCenter::OperationError.new('command_id_conflict', status: :conflict) unless matches

    command
  end
end
