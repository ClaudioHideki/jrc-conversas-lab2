# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AgentStatesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    render_state
  end

  def update
    authorize_contact_center!(:operate?)
    attributes = params.require(:agent_state).permit(:state, :command_id, :expected_state_version, :queue_id, :reason_code)
    %i[state command_id expected_state_version].each { |key| attributes.require(key) }
    JrcContactCenter::AgentStateManager.new(account: Current.account, account_user: Current.account_user)
                                       .transition(**attributes.to_h.symbolize_keys)
    render_state
  end

  private

  def render_state
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user)
    render json: base_payload.merge(item: snapshot.call)
  end
end
