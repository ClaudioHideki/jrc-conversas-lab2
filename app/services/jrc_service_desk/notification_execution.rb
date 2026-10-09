# frozen_string_literal: true

# The native SendReplyJob retains ownership of the provider boundary.
class JrcServiceDesk::NotificationExecution
  TERMINAL = %w[blocked sent delivered read failed].freeze
  CONTROLLERS = %w[jrc_flow_run_id nico_delegation relationship_survey_id].freeze

  def initialize(message)
    @message = message
  end

  def self.payload_digest(message, row)
    JrcServiceDesk::NotificationPayload.new(message, row).digest
  end

  def perform(&)
    @row = JrcServiceDesk::NotificationDelivery.find_by(id: @message.content_attributes['service_desk_delivery_id'],
                                                        account_id: @message.account_id, message_id: @message.id,
                                                        conversation_id: @message.conversation_id)
    return unless @row && claim

    @row.reload
    @message.reload
    blocker = current_blocker
    return reject(blocker) if blocker

    member = @row.execution_membership.account_user
    JrcServiceDesk::NativeExecutionContext.with(user: member.user, account: @row.account, account_user: member, &)
    state = persist_result(@message.reload)
    record_first_response(state)
  rescue StandardError
    preserve_uncertainty
  end

  private

  def claim
    @row.with_lock do
      if @row.state == 'dispatching'
        @row.update!(state: 'unknown', reason: 'previous_dispatch_result_unknown')
        next false
      end
      next false unless @row.state == 'queued'

      blocker = current_blocker
      next reject(blocker) if blocker

      @row.update!(state: 'dispatching', dispatch_started_at: Time.current)
      true
    end
  end

  def current_blocker
    reason = JrcServiceDesk::NotificationEngine.blocker(@row)
    reason ||= 'incompatible_delivery_control' if CONTROLLERS.any? { |key| @message.content_attributes[key].present? }
    digest = self.class.payload_digest(@message, @row)
    reason ||= 'message_payload_changed' unless @row.payload_digest.present? && @row.payload_digest == digest
    reason
  end

  def reject(reason)
    @row.with_lock { @row.update!(state: 'blocked', reason: reason) }
    @message.update!(status: :failed, external_error: 'Service Desk delivery blocked by current policy')
    false
  end

  def result_state(message)
    return 'failed' if message.failed?
    return message.status if %w[delivered read].include?(message.status)
    return 'sent' if message.source_id.present?

    'unknown'
  end

  def preserve_current?(state)
    %w[blocked delivered read].include?(@row.state) || (state == 'unknown' && %w[sent failed].include?(@row.state))
  end

  def persist_result(message)
    state = result_state(message)
    @row.with_lock do
      next @row.state if preserve_current?(state)

      @row.update!(state: state, provider_id: message.source_id, sent_at: sent_at(state), reason: result_reason(state))
      state
    end
  end

  def sent_at(state)
    @row.sent_at || (%w[sent delivered read].include?(state) ? Time.current : nil)
  end

  def result_reason(state)
    return 'provider_result_unverified' if state == 'unknown'
    return 'provider_failure' if state == 'failed'

    nil
  end

  def record_first_response(state)
    return unless %w[sent delivered read].include?(state)

    JrcServiceDesk::FirstResponseJob.perform_later(@message.id, JrcServiceDesk::NativeResponseRecorder.evidence(@message))
  end

  def preserve_uncertainty
    @row&.with_lock do
      next if TERMINAL.include?(@row.state)

      @row.update!(state: 'unknown', reason: 'provider_result_unknown')
    end
  end
end
