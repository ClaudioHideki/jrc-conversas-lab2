# frozen_string_literal: true

class JrcServiceDesk::DeliveryPresenter
  def initialize(context:)
    @context = context
  end

  def call(row)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::DeliveryAccess.new(@context).allowed?(row)

    row.slice(:state, :channel, :recipient, :reason, :provider_id, :attempt_number).symbolize_keys
       .merge(identity(row), configuration(row), timestamps(row), permissions: permissions(row))
  end

  private

  def identity(row)
    { id: row.id.to_s, ticket_note_id: row.ticket_note_id&.to_s, ticket_event_id: row.ticket_event_id&.to_s,
      original_delivery_id: row.original_delivery_id&.to_s, provider: row.conversation&.inbox&.channel_type,
      execution_account_user_id: row.execution_membership.account_user_id.to_s }
  end

  def configuration(row)
    policy = row.notification_policy_version
    { template_version: policy&.template_version, policy_version: policy&.version, template: policy&.template,
      content: policy && JrcServiceDesk::NotificationSource.render(policy.template, fields(row)) }
  end

  def fields(row)
    row.source_snapshot.presence || JrcServiceDesk::NotificationSource.new(row.ticket_note || row.ticket_event).fields
  end

  def timestamps(row)
    %i[created_at dispatch_started_at sent_at delivered_at read_at].index_with { |key| row.public_send(key)&.iso8601(6) }
  end

  def permissions(row)
    manage = @context.capability?(:notifications_manage)
    { resend: manage && %w[blocked failed sent delivered read].include?(row.state), reconcile: manage && row.state == 'unknown' }
  end
end
