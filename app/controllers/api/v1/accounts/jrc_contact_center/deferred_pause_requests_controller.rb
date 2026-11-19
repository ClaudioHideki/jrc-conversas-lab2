# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::DeferredPauseRequestsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def create
    record = with_current_operating_authority { manager.request!(request_values) }
    render_state(record)
  end

  def destroy
    record = with_current_operating_authority { manager.cancel!(params.require(:request_id)) }
    render_state(record)
  end

  private

  def manager
    JrcContactCenter::DeferredPauseManager.new(account: Current.account, member: Current.account_user)
  end

  def request_values
    document = params.require(:deferred_pause_request)
    keys = JrcContactCenter::DeferredPauseInput::FIELDS
    valid = document.is_a?(ActionController::Parameters) && (document.keys.map(&:to_sym) - keys).empty?
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid

    document.keys.to_h { |key| [key.to_sym, document[key]] }
  end

  def render_state(record)
    with_current_operating_authority do
      response.headers['Cache-Control'] = 'no-store'
      snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user)
      receipt = JrcContactCenter::DeferredPauseProjection.new(account: Current.account, member: Current.account_user).call(record)
      render json: base_payload.merge(item: snapshot.operator_payload, receipt: receipt)
    end
  end
end
