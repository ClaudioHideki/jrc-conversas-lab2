# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QualificationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    target = attendance
    JrcContactCenter::QualificationManager.ensure_voice!(target) if target.is_a?(JrcContactCenter::CallSession)
    records = scope.where(target.is_a?(Conversation) ? { conversation_id: target.id } : { call_session_id: target.id })
    render json: base_payload.merge(items: records.order(created_at: :desc).includes(account_user: :user).map(&:operational_payload),
                                   policy: JrcContactCenter::AcwPolicy.new(account: Current.account).call,
                                   attendance: target.as_json(only: %i[id status ended_at]),
                                   agent: JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user).call)
  end

  def create
    authorize_contact_center!(:operate?)
    target = attendance
    record = manager.start!(**(target.is_a?(Conversation) ? { conversation: target } : { call_session: target }))
    render json: base_payload.merge(item: record.operational_payload)
  end

  def update
    authorize_contact_center!(:operate?)
    record = scope.where(account_user: Current.account_user).find(params[:id])
    record = manager.complete!(record, params.require(:qualification).permit(:reason_code, :outcome_code, :notes).to_h.symbolize_keys)
    render json: base_payload.merge(item: record.operational_payload,
                                   agent: JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user).call)
  end

  private

  def scope
    records = JrcContactCenter::Qualification.where(account: Current.account)
    contact_center_access.full_access? ? records : records.where(account_user: Current.account_user)
  end

  def manager
    JrcContactCenter::QualificationManager.new(account: Current.account, member: Current.account_user)
  end

  def attendance
    return contact_center_access.call_sessions.find(params[:call_session_id]) if params[:call_session_id].present?

    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    unless (conversation.inbox.whatsapp? || conversation.inbox.twilio_whatsapp?) &&
           (contact_center_access.full_access? || conversation.assignee_id == Current.user.id)
      raise Pundit::NotAuthorizedError
    end
    authorize conversation, :show?
    conversation
  end
end
