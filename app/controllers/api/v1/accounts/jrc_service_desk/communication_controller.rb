class Api::V1::Accounts::JrcServiceDesk::CommunicationController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  before_action :authorize_ticket_read, only: %i[timeline_attachment resend_preview resend reconcile]
  rescue_from ::JrcServiceDesk::PublicationPreviewError, with: :preview_invalid
  rescue_from ::JrcServiceDesk::AttachmentScanError, with: :scan_unavailable

  def composer_options
    raise ArgumentError unless query_values.empty?

    authorize strict_ticket, :add_note?
    render json: base_payload.merge(composer: ::JrcServiceDesk::ComposerProjection.new(ticket: strict_ticket, context: operational_context).call)
  end

  def recipient_preferences
    authorize strict_ticket, :view_customer?
    raise Pundit::NotAuthorizedError unless operational_context.capability?(:notifications_manage)

    render json: base_payload.merge(ticket_id: strict_ticket.id.to_s,
                                    channels: ::JrcServiceDesk::ContactNotificationPreferences.channels(strict_ticket.requester))
  end

  def update_recipient_preferences
    values = body_values(%w[channels])
    channels = ::JrcServiceDesk::ContactNotificationPreferences.new(user_context: pundit_user)
                                                              .call(ticket_id: strict_ticket.id, channels: values.fetch('channels'))
    render json: base_payload.merge(applied: true, ticket_id: strict_ticket.id.to_s, channels: channels)
  end

  def preview
    authorize strict_ticket, :add_note?
    values = body_values(%w[note files])
    uploads = ::JrcServiceDesk::InteractionAttachments.prepare(values.fetch('files', []))
    preview = ::JrcServiceDesk::InteractionPreview.new(ticket: strict_ticket, context: operational_context)
    result = preview.call(attributes: values.fetch('note'), file_fingerprints: uploads.map { |file| file.except(:io).stringify_keys })
    render json: base_payload.merge(preview: result)
  end

  def timeline
    authorize strict_ticket, :show?
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[cursor per_page])
    result = ::JrcServiceDesk::TicketTimeline.new(ticket: strict_ticket, context: operational_context).call(**values.symbolize_keys)
    render json: base_payload.merge(ticket_id: strict_ticket.id.to_s, unit_id: strict_ticket.unit_id.to_s, timeline: result)
  end

  def notification_policies
    values = ::JrcServiceDesk::Input.attributes(query_values, %w[unit_id])
    context = operational_context
    raise Pundit::NotAuthorizedError unless context.capability?(:notifications_manage)

    unit = context.unit_scope.find(::JrcServiceDesk::Input.id(values.fetch('unit_id')))
    authorize unit, :show?
    rows = ::JrcServiceDesk::NotificationPolicyVersion.where(account_id: context.account.id, unit_id: unit.id).order(:event_type, :channel,
                                                                                                                     version: :desc)
    render json: base_payload.merge(unit_id: unit.id.to_s, event_types: ::JrcServiceDesk::NotificationEvent::TYPES,
                                    policies: rows.map { |row| policy_payload(row) })
  end

  def timeline_attachment
    raise ArgumentError unless query_values.empty?

    file = ::JrcServiceDesk::TimelineAttachment.new(ticket: strict_ticket, context: operational_context).call(
      kind: params[:kind], record_id: params[:record_id], attachment_id: params[:attachment_id]
    )
    send_data file.download, filename: file.filename.to_s, type: 'application/octet-stream', disposition: 'attachment'
  end

  def resend_preview
    values = body_values(%w[reason])
    preview = ::JrcServiceDesk::NotificationResendPreview.new(row: strict_delivery, context: operational_context)
    render json: base_payload.merge(preview: preview.call(reason: values.fetch('reason')))
  end

  def resend
    values = body_values(%w[reason receipt idempotency_key])
    row = ::JrcServiceDesk::ResendNotificationService.new(user_context: pundit_user).call(
      delivery: strict_delivery, receipt: values.fetch('receipt'), reason: values.fetch('reason'), idempotency_key: values.fetch('idempotency_key')
    )
    acknowledged(strict_ticket, 'resend_notification', result_id: row.id)
  end

  def reconcile
    raise ArgumentError unless body_values([]).empty?

    row = strict_delivery
    raise Pundit::NotAuthorizedError unless operational_context.capability?(:notifications_manage)

    ::JrcServiceDesk::NotificationReceipt.new(row).call
    render json: base_payload.merge(ticket_id: strict_ticket.id.to_s, unit_id: strict_ticket.unit_id.to_s,
                                    delivery: ::JrcServiceDesk::DeliveryPresenter.new(context: operational_context).call(row.reload))
  end

  private

  def authorize_ticket_read
    authorize strict_ticket, :show?
  end

  def operational_context
    ::JrcServiceDesk::OperationalContext.new(pundit_user)
  end

  def strict_delivery
    row = ::JrcServiceDesk::NotificationDelivery.where(account_id: strict_ticket.account_id, unit_id: strict_ticket.unit_id,
                                                       ticket_id: strict_ticket.id).find(::JrcServiceDesk::Input.id(params[:delivery_id]))
    ::JrcServiceDesk::DeliveryPresenter.new(context: operational_context).call(row)
    row
  end

  def policy_payload(row)
    { id: row.id.to_s, event_type: row.event_type, channel: row.channel, enabled: row.enabled,
      version: row.version, template: row.template, template_version: row.template_version, inbox_id: row.inbox_id&.to_s,
      ticket_type_id: row.ticket_type_id&.to_s, service_id: row.service_id&.to_s,
      execution_account_user_id: row.published_by_membership.account_user_id.to_s, created_at: row.created_at.iso8601(6), digest: row.digest }
  end

  def preview_invalid
    render json: { code: 'preview_invalid', error: 'Publication preview expired or changed; review the current preview' }, status: :conflict
  end

  def scan_unavailable
    render json: { code: 'attachment_scan_unavailable', error: 'Attachment awaits a verified malware scan' }, status: :conflict
  end
end
