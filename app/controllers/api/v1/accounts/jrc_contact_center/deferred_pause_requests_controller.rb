# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::DeferredPauseRequestsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }
  rescue_from JrcApprovals::Error, with: :render_approval_unavailable

  def create
    record = with_current_operating_authority do
      values = request_values
      params.key?(:expected_approval_digest) ? manager.request_reviewed!(values, expected_approval_digest: params[:expected_approval_digest]) :
        manager.request!(values)
    end
    render_state(record)
  end

  def preview
    with_current_operating_authority do
      context = { account: Current.account, account_user: Current.account_user, user: Current.user }
      preview = JrcContactCenter::PauseApprovalIntent.new(context: context).call(request_values)
      render json: base_payload.merge(account_user_id: Current.account_user.id.to_s, preview: preview)
    end
  end

  def apply
    values = strict_values(%i[request_id expected_state_version])
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless values.keys.sort == %i[expected_state_version request_id]
    record = with_current_operating_authority { manager.apply!(**values) }
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
    strict_values(JrcContactCenter::DeferredPauseInput::FIELDS)
  end

  def strict_values(keys)
    document = params.require(:deferred_pause_request)
    valid = document.is_a?(ActionController::Parameters) && (document.keys.map(&:to_sym) - keys).empty?
    raise JrcContactCenter::OperationError, 'invalid_deferred_pause' unless valid

    document.keys.to_h { |key| [key.to_sym, document[key]] }
  end

  def render_approval_unavailable
    render json: base_payload.merge(error: 'pause_approval_unavailable'), status: :conflict
  end

  def render_state(record)
    with_current_operating_authority do
      snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user)
      receipt = JrcContactCenter::DeferredPauseProjection.new(account: Current.account, member: Current.account_user).call(record)
      render json: base_payload.merge(item: snapshot.operator_payload, receipt: receipt)
    end
  end
end
