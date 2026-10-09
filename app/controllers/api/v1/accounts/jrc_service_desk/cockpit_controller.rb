# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::CockpitController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  rescue_from ::JrcServiceDesk::LifecycleDependencyError, with: :operational_dependency_unavailable
  rescue_from ::JrcServiceDesk::PublicationPreviewError, with: :publication_preview_invalid
  def show
    raise ArgumentError unless query_values.empty?

    authorize strict_ticket, :show?
    render json: base_payload.merge(ticket: presenter.ticket(strict_ticket), cockpit: cockpit_payload)
  end

  def board
    model = ::JrcServiceDesk::OperationsBoardQuery::MODELS.fetch(query_values.fetch('kind'))
    authorize model, :index?
    payload = ::JrcServiceDesk::OperationsBoardQuery.new(context: pundit_user, parameters: query_values).call
    render json: base_payload.merge(payload)
  end

  # Export and AI use exactly the same policy-filtered projection as the cockpit.
  def export
    raise ArgumentError unless query_values.empty?

    authorize strict_ticket, :show?
    render json: base_payload.merge(ticket: presenter.ticket(strict_ticket), cockpit: cockpit_payload,
                                    generated_at: Time.current.iso8601(6), projection: 'authorized_service_desk_cockpit_v2')
  end

  def add_interaction
    authorize strict_ticket, :add_note?
    values = body_values(%w[note files preview_receipt])
    command = ::JrcServiceDesk::AddNoteService.new(user_context: pundit_user)
    note = command.call(ticket_id: strict_ticket.id,
                        attributes: values.fetch('note'), files: values.fetch('files', []),
                        preview_receipt: values['preview_receipt'], idempotency_key: request.headers['Idempotency-Key'])
    acknowledged(strict_ticket, 'add_interaction', result_id: note.id, status: :created)
  end

  def create_task
    authorize strict_ticket, :show?
    values = body_values(%w[task])
    command = ::JrcServiceDesk::CreateTaskService.new(user_context: pundit_user)
    row = command.call(ticket_id: strict_ticket.id,
                       attributes: values.fetch('task'), idempotency_key: request.headers['Idempotency-Key'])
    acknowledged(strict_ticket, 'create_task', result_id: row.id, status: :created)
  end

  def update_task
    authorize strict_ticket, :show?
    values = body_values(%w[task expected_lock_version])
    command = ::JrcServiceDesk::UpdateTaskService.new(user_context: pundit_user)
    row = command.call(ticket_id: strict_ticket.id,
                       task_id: ::JrcServiceDesk::Input.id(params[:record_id]), attributes: values.fetch('task'),
                       expected_lock_version: values.fetch('expected_lock_version'))
    acknowledged(strict_ticket, 'update_task', result_id: row.id)
  end

  def request_approval
    authorize strict_ticket, :show?
    values = body_values(%w[approval])
    command = ::JrcServiceDesk::CreateApprovalService.new(user_context: pundit_user)
    row = command.call(ticket_id: strict_ticket.id,
                       attributes: values.fetch('approval'), idempotency_key: request.headers['Idempotency-Key'])
    acknowledged(strict_ticket, 'request_approval', result_id: row.id, status: :created)
  end

  def decide_approval
    authorize strict_ticket, :show?
    values = body_values(%w[decision expected_lock_version])
    command = ::JrcServiceDesk::DecideApprovalService.new(user_context: pundit_user)
    row = command.call(ticket_id: strict_ticket.id,
                       approval_id: ::JrcServiceDesk::Input.id(params[:record_id]), attributes: values.fetch('decision'),
                       expected_lock_version: values.fetch('expected_lock_version'))
    acknowledged(strict_ticket, 'decide_approval', result_id: row.id)
  end

  def escalate_approval
    authorize strict_ticket, :show?
    values = body_values(%w[escalation expected_lock_version])
    row = ::JrcServiceDesk::EscalateApprovalService.new(user_context: pundit_user).call(
      ticket_id: strict_ticket.id, approval_id: params[:record_id], attributes: values.fetch('escalation'),
      expected_lock_version: values.fetch('expected_lock_version')
    )
    acknowledged(strict_ticket, 'escalate_approval', result_id: row.id)
  end

  def evaluate_clocks
    raise ArgumentError unless body_values([]).empty?

    authorize strict_ticket, :update?
    row = ::JrcServiceDesk::EvaluateClocksService.new(user_context: pundit_user).call(ticket_id: strict_ticket.id)
    render json: base_payload.merge(applied: true, ticket_id: row.id.to_s, operation: 'evaluate_clocks')
  end

  def attachment
    authorize strict_ticket, :show?
    note = strict_ticket.ticket_notes.find(::JrcServiceDesk::Input.id(params[:record_id]))
    authorize note, :show?
    file = note.files.find(::JrcServiceDesk::Input.id(params[:attachment_id]))
    if file.blob.metadata['service_desk_scan_state'] != 'clean'
      return render json: { code: 'attachment_scan_unavailable', error: 'Attachment awaits a verified malware scan' }, status: :conflict
    end

    send_data file.download, filename: file.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  def claim_next
    authorize ::JrcServiceDesk::Ticket, :index?
    values = body_values(%w[unit_id])
    command = ::JrcServiceDesk::ClaimNextService.new(user_context: pundit_user)
    ticket = command.call(unit_id: values.fetch('unit_id'),
                          idempotency_key: request.headers['Idempotency-Key'])
    render json: base_payload.merge(applied: true, operation: 'claim_next', ticket_id: ticket&.id&.to_s,
                                    unit_id: ::JrcServiceDesk::Input.id(values.fetch('unit_id')).to_s,
                                    assignee_account_user_id: ticket&.assignee_membership&.account_user_id&.to_s)
  end

  def create_incident
    values = body_values(%w[unit_id incident])
    unit = ::JrcServiceDesk::OperationalContext.new(pundit_user).unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize ::JrcServiceDesk::Incident.new(account: Current.account, unit: unit), :create?
    command = ::JrcServiceDesk::CreateIncidentService.new(user_context: pundit_user)
    row = command.call(unit_id: values.fetch('unit_id'),
                       attributes: values.fetch('incident'), idempotency_key: request.headers['Idempotency-Key'])
    render json: base_payload.merge(applied: true, operation: 'create_incident', incident: operation_payload('incidents', row)), status: :created
  end

  def show_incident
    raise ArgumentError unless query_values.empty?

    row = policy_scope(::JrcServiceDesk::Incident).find(::JrcServiceDesk::Input.id(params[:incident_id]))
    authorize row, :show?
    render json: base_payload.merge(incident: operation_payload('incidents', row))
  end

  def publish_notification_policy
    values = body_values(%w[unit_id policy])
    authorize policy_scope(::JrcServiceDesk::Unit).find(::JrcServiceDesk::Input.id(values.fetch('unit_id'))), :show?
    command = ::JrcServiceDesk::PublishNotificationPolicyService.new(user_context: pundit_user)
    row = command.call(unit_id: values.fetch('unit_id'),
                       attributes: values.fetch('policy'))
    render json: base_payload.merge(applied: true, operation: 'publish_notification_policy', version: row.version, enabled: row.enabled),
           status: :created
  end

  def update_incident
    values = body_values(%w[unit_id incident expected_lock_version])
    row = policy_scope(::JrcServiceDesk::Incident).find(::JrcServiceDesk::Input.id(params[:incident_id]))
    authorize row, :update?
    command = ::JrcServiceDesk::UpdateIncidentService.new(user_context: pundit_user)
    row = command.call(unit_id: values.fetch('unit_id'),
                       incident_id: params[:incident_id], attributes: values.fetch('incident'),
                       expected_lock_version: values.fetch('expected_lock_version'))
    render json: base_payload.merge(applied: true, operation: 'update_incident', incident: operation_payload('incidents', row))
  end

  private

  def publication_preview_invalid
    render json: { code: 'preview_invalid', error: 'Publication preview expired or changed; review the current preview' }, status: :conflict
  end

  def operational_dependency_unavailable
    render json: { code: 'operational_dependency_unavailable' }, status: :unprocessable_entity
  end

  def cockpit_payload
    ::JrcServiceDesk::CockpitProjection.new(ticket: strict_ticket, context: pundit_user).call
  end

  def operation_payload(kind, row)
    context = ::JrcServiceDesk::OperationalContext.new(pundit_user)
    ::JrcServiceDesk::OperationsPresenter.new(context: context).call(kind, row)
  end
end
