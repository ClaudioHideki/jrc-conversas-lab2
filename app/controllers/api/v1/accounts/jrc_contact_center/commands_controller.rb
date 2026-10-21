# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::CommandsController < Api::V1::Accounts::JrcContactCenter::BaseController
  ACTIONS = { 'answer' => 'sip_webrtc', 'hangup' => 'sip_webrtc', 'hold' => 'hold', 'resume' => 'hold',
              'transfer_blind' => 'transfer_blind', 'transfer_attended' => 'transfer_attended', 'originate' => 'originate' }.freeze

  def index
    authorize_contact_center!(:operate?)
    render json: base_payload.merge(items: scoped_commands.order(requested_at: :desc).limit(100).map { |command| serialize(command) })
  end

  def show
    authorize_contact_center!(:operate?)
    render json: base_payload.merge(item: serialize(scoped_commands.find(params[:id])))
  end

  def create
    authorize_contact_center!(:operate?)
    attributes = command_params
    session = validate_session!(attributes)
    adapter = JrcContactCenter::Providers::JrcPabxAdapter.new(account: Current.account)
    capability = ACTIONS.fetch(attributes.fetch(:action))
    raise JrcContactCenter::Providers::BaseAdapter::CapabilityUnavailable, capability unless adapter.capabilities[capability] == 'available'

    options = attributes.slice(:command_id, :reason_code, :expected_state_version).merge(call_session: session)
    command = JrcContactCenter::CommandDispatcher.new(account: Current.account, actor_account_user: Current.account_user, adapter: adapter)
                                                 .call(action: attributes.fetch(:action), parameters: attributes.fetch(:parameters, {}), **options)
    render json: base_payload.merge(item: serialize(command)), status: :accepted
  end

  private

  def scoped_commands
    scope = JrcContactCenter::Command.where(account: Current.account)
    contact_center_access.full_access? ? scope : scope.where(actor_account_user: Current.account_user)
  end

  def command_params
    attributes = params.require(:command).permit(:action, :command_id, :call_session_id, :expected_state_version, :reason_code,
                                                 parameters: [:destination]).to_h.symbolize_keys
    raise JrcContactCenter::OperationError, 'invalid_command_action' unless ACTIONS.key?(attributes[:action])
    raise JrcContactCenter::OperationError, 'command_id_required' if attributes[:command_id].blank?

    attributes
  end

  def validate_session!(attributes)
    return if attributes[:action] == 'originate'

    session = contact_center_access.call_sessions.find(attributes.fetch(:call_session_id, nil))
    matches = attributes[:expected_state_version].present? && attributes[:expected_state_version].to_s == session.lock_version.to_s
    raise JrcContactCenter::OperationError.new('state_conflict', status: :conflict) unless matches
    raise JrcContactCenter::OperationError, 'call_already_ended' if %w[ended failed].include?(session.status)

    ensure_owned_leg!(session)

    session
  end

  def ensure_owned_leg!(session)
    return if contact_center_access.full_access?

    owned = session.legs.where(account_user: Current.account_user)
                   .where.not(status: JrcContactCenter::AgentStateSnapshot::TERMINAL_LEG_STATES).exists?
    raise Pundit::NotAuthorizedError unless owned
  end

  def serialize(command)
    command.as_json(only: %i[id command_id action status call_session_id requested_at completed_at expected_state_version])
  end
end
