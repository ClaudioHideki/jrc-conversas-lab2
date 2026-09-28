# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::LifecycleController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  rescue_from ::JrcServiceDesk::LifecycleDependencyError, with: :dependency_missing

  def show
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[page])
    authorize strict_ticket, :inspect?, policy_class: ::JrcServiceDesk::LifecycleActionPolicy
    render json: reader.call(page: values.fetch('page', 1))
  end

  def create
    authorize strict_ticket, :apply?, policy_class: ::JrcServiceDesk::LifecycleActionPolicy
    values = body_values(::JrcServiceDesk::LifecycleTransitionService::FIELDS)
    result = ::JrcServiceDesk::LifecycleTransitionService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, attributes: values, idempotency_key: request.headers['Idempotency-Key'])
    acknowledged(result.ticket, 'lifecycle', result_id: result.id)
  end

  def transition
    raise ArgumentError unless query_values.empty?
    authorize strict_ticket, :view_history?
    result = strict_ticket.lifecycle_transitions.find(::JrcServiceDesk::Input.id(params[:transition_id]))
    render json: base_payload.merge(transition: reader.transition(result))
  end

  private

  def reader
    ::JrcServiceDesk::LifecycleReadService.new(user_context: pundit_user, ticket: strict_ticket)
  end

  def dependency_missing(_error)
    render json: { error: 'Explicit compatible SLA/calendar configuration is required; no operation was applied', code: 'lifecycle_dependency' }, status: :unprocessable_entity
  end
end
