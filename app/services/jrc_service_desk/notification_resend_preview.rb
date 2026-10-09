# frozen_string_literal: true

class JrcServiceDesk::NotificationResendPreview
  PURPOSE = 'service_desk_notification_resend'
  STATES = %w[blocked failed sent delivered read].freeze

  def initialize(row:, context:)
    @row = row
    @context = context
  end

  def call(reason:)
    plan = plan(reason)
    plan.merge(receipt: verifier.generate(binding(plan), expires_in: 5.minutes, purpose: PURPOSE),
               expires_at: 5.minutes.from_now.iso8601(6))
  end

  def verify!(receipt, reason:)
    current = plan(reason)
    raise JrcServiceDesk::PublicationPreviewError unless verifier.verified(receipt, purpose: PURPOSE) == binding(current)

    current
  end

  def candidate
    source = @row.ticket_note || @row.ticket_event
    policy = JrcServiceDesk::NotificationEngine.current_policy(source, @row.channel)
    @row.dup.tap do |row|
      if row.source_snapshot.blank?
        snapshot = JrcServiceDesk::NotificationSource.new(source).snapshot
        row.assign_attributes(source_snapshot: snapshot, source_digest: JrcServiceDesk::CanonicalJson.digest(snapshot))
      end
      row.assign_attributes(notification_policy_version: policy, execution_membership: membership,
                            recipient: row.conversation && JrcServiceDesk::NotificationEngine.recipient(row.conversation, row.channel),
                            message: nil, payload_digest: nil, provider_id: nil, state: 'queued', reason: nil)
    end
  end

  private

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end

  def membership
    @context.active_memberships.where(unit_id: @row.unit_id).take!
  end

  def authorize!
    allowed = @context.capability?(:notifications_manage) && @context.capability?(:customer_publish) && @context.unit_allowed?(@row.unit)
    raise Pundit::NotAuthorizedError unless allowed && JrcServiceDesk::DeliveryAccess.new(@context).allowed?(@row)
    raise ArgumentError, 'Unknown or active attempts must be reconciled' unless STATES.include?(@row.state)
  end

  def plan(reason)
    authorize!
    raise ArgumentError, 'Explicit resend reason required' unless reason.is_a?(String) && reason.strip.present? && reason.length <= 2000

    row = candidate
    blocker = JrcServiceDesk::NotificationEngine.blocker(row)
    scope.merge(reason: reason, channel: row.channel, recipient: row.recipient, source_digest: row.source_digest,
                available: blocker.nil?, unavailable_reason: blocker).merge(configuration(row))
  end

  def scope
    { account_id: @row.account_id.to_s, unit_id: @row.unit_id.to_s, ticket_id: @row.ticket_id.to_s,
      delivery_id: @row.id.to_s, revision: @row.lock_version }
  end

  def configuration(row)
    policy = row.notification_policy_version
    { policy_version_id: policy&.id&.to_s, policy_digest: policy&.digest,
      content: policy && JrcServiceDesk::NotificationSource.render(policy.template, row.source_snapshot) }
  end

  def binding(plan)
    { 'digest' => JrcServiceDesk::CanonicalJson.digest(plan), 'account_user_id' => @context.account_user.id }
  end
end
