# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::QualificationsController < Api::V1::Accounts::JrcContactCenter::BaseController
  def index
    authorize_contact_center!
    target = attendance
    JrcContactCenter::QualificationManager.ensure_voice!(target) if target.is_a?(JrcContactCenter::CallSession)
    records = scope.where(target.is_a?(Conversation) ? { conversation_id: target.id } : { call_session_id: target.id })
    items = records.order(created_at: :desc).includes(account_user: :user).map { |record| qualification_payload(record) }
    render json: base_payload.merge(items: items,
                                   policy: JrcContactCenter::AcwPolicy.new(account: Current.account).call,
                                   attendance: target.as_json(only: %i[id status ended_at]),
                                   agent: operator_snapshot)
  end

  def create
    with_current_operating_authority do
      target = attendance
      record = manager.start!(**(target.is_a?(Conversation) ? { conversation: target } : { call_session: target }))
      render json: base_payload.merge(item: qualification_payload(record))
    end
  end

  def update
    with_current_operating_authority do
      record = scope.where(account_user: Current.account_user).find(params[:id])
      authorize_qualification_origin!(record)
      if params.key?(:expected_draft_revision) && !record.completed_at
        JrcContactCenter::QualificationDraftRevision.check!(record, params[:expected_draft_revision])
      end
      record = manager.complete!(record, qualification_attributes)
      render json: base_payload.merge(item: qualification_payload(record), agent: operator_snapshot)
    end
  end

  def form_context
    with_current_operating_authority do
      record = scope.where(account_user: Current.account_user).find(params[:id])
      authorize_qualification_origin!(record)
      reason = params[:reason_code]
      valid = reason.is_a?(String) && reason.length <= 100 && reason.exclude?("\0")
      raise JrcContactCenter::OperationError, 'invalid_qualification_form_context' unless valid

      response.headers['Cache-Control'] = 'no-store'
      item = { id: record.id, account_id: record.account_id, account_user_id: record.account_user_id, reason_code: reason }
      item.merge!(JrcContactCenter::QualificationForms.new(record).private_payload(reason: reason))
      render json: base_payload.merge(item: item)
    end
  end

  def draft
    with_current_operating_authority do
      record = scope.where(account_user: Current.account_user).find(params[:id])
      authorize_qualification_origin!(record)
      record = manager.save_draft!(record, draft_attributes, expected_revision: params[:expected_draft_revision])
      render json: base_payload.merge(item: qualification_payload(record), agent: operator_snapshot)
    end
  end

  private

  def qualification_payload(record)
    response.headers['Cache-Control'] = 'no-store'
    JrcContactCenter::QualificationProjection.new(account: Current.account, member: Current.account_user).call(record)
  end

  def qualification_attributes
    document = params.require(:qualification)
    values = document.permit(:reason_code, :outcome_code, :notes).to_h.symbolize_keys
    return values unless document.key?(JrcContactCenter::QualificationForms::KEY)

    input = document[JrcContactCenter::QualificationForms::KEY]
    values.merge(JrcContactCenter::QualificationForms::KEY => input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input)
  end

  def draft_attributes
    document = params.require(:qualification)
    raise JrcContactCenter::OperationError, 'invalid_qualification_draft' unless document.is_a?(ActionController::Parameters)

    valid = JrcContactCenter::QualificationDraft::FIELDS.all? do |field|
      !document.key?(field) || document[field].nil? || document[field].is_a?(String)
    end
    raise JrcContactCenter::OperationError, 'invalid_qualification_draft' unless valid

    qualification_attributes
  end

  def authorize_qualification_origin!(record)
    if record.call_session_id
      contact_center_access.call_sessions.find(record.call_session_id)
    else
      authorize record.conversation, :show?
      raise Pundit::NotAuthorizedError unless contact_center_access.full_access? || record.conversation.assignee_id == Current.user.id
    end
  end

  def operator_snapshot
    response.headers['Cache-Control'] = 'no-store'
    JrcContactCenter::AgentStateSnapshot.new(account_user: Current.account_user).operator_payload
  end

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
