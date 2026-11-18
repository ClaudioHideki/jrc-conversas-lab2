# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AgentStatesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    render_state
  end

  def update
    authorize_contact_center!(:operate?)
    document = params.require(:agent_state)
    attributes = document.permit(:state, :command_id, :expected_state_version, :queue_id, :reason_code, :justification)
    %i[state command_id expected_state_version].each { |key| attributes.require(key) }
    values = attributes.to_h.symbolize_keys
    # Validate this bounded private value before any persistence, including malformed arrays/hashes.
    values[:justification] = document[:justification] if document.key?(:justification)
    JrcContactCenter::AgentStateManager.new(account: Current.account, account_user: Current.account_user).transition(**values)
    render_state
  end

  private

  def render_state
    response.headers['Cache-Control'] = 'no-store'
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user)
    render json: base_payload.merge(item: snapshot.operator_payload)
  end
end
