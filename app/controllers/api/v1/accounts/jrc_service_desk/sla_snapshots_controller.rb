# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::SlaSnapshotsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def create
    values = body_values(%w[snapshot])
    candidate = ::JrcServiceDesk::SlaSnapshot.new(account: Current.account, unit: strict_ticket.unit, ticket: strict_ticket)
    authorize candidate, :create?
    snapshot = ::JrcServiceDesk::RecordSlaSnapshotService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, attributes: values.fetch('snapshot'))
    render json: snapshot_payload(snapshot, receipt: true).merge(applied: true)
  end

  def show
    raise ArgumentError unless query_values.empty?

    authorize strict_ticket, :show?
    snapshot = policy_scope(::JrcServiceDesk::SlaSnapshot)
      .where(account_id: Current.account.id, unit_id: strict_ticket.unit_id, ticket_id: strict_ticket.id)
      .find(::JrcServiceDesk::Input.id(params[:snapshot_id]))
    authorize snapshot, :show?
    render json: snapshot_payload(snapshot)
  end

  private

  def snapshot_payload(snapshot, receipt: false)
    base_payload.merge(unit_id: snapshot.unit_id.to_s, ticket_id: snapshot.ticket_id.to_s,
                       snapshot: ::JrcServiceDesk::SlaSnapshotPresenter.new(user_context: pundit_user).call(snapshot, receipt: receipt))
  end
end
