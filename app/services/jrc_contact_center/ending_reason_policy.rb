# frozen_string_literal: true

# Own-only projection of a database-frozen call catalogue; never the current manager catalogue.
class JrcContactCenter::EndingReasonPolicy
  KEY = 'ending_reason_snapshot_v1'

  def self.required_call?(session, leg)
    version_id = JrcContactCenter::CallSession.where(account_id: session.account_id).where(id: session.id).pick(:ending_reason_version_id)
    return false unless version_id

    version = JrcContactCenter::EndingReasonVersion.where(account_id: session.account_id).find(version_id)
    version.required_for?(leg.queue_id || session.current_queue_id)
  end

  def initialize(record)
    @record = record
  end

  def private_payload
    context = snapshot
    return {} unless context

    authorize!(context)
    version = frozen_version(context)
    { 'ending_reason_context' => { 'revision' => version.revision, 'integrity_sha256' => version.integrity_sha256,
                                   'required' => context.fetch('required'), 'options' => version.options } }
  end

  def registered?(reason)
    reason_option?(private_payload['ending_reason_context'], reason)
  end

  def validate!(reason, complete:)
    context = private_payload['ending_reason_context']
    return unless context&.fetch('required')
    return if reason.blank? && !complete
    return if reason_option?(context, reason)

    raise JrcContactCenter::OperationError, 'registered_ending_reason_required'
  end

  def snapshot
    event = JrcContactCenter::AgentStateEvent.where(account_id: @record.account_id, account_user_id: @record.account_user_id,
                                                    source: 'jrc_conversas', state: 'acw',
                                                    external_event_id: "qualification:#{@record.id}:pending").pick(:metadata)
    context = event&.fetch(KEY, nil)
    if @record.call_session_id && !context && @record.call_session.reload.ending_reason_version_id
      raise JrcContactCenter::OperationError, 'ending_reason_origin_unavailable'
    end

    context
  end

  private

  def reason_option?(context, reason)
    return false unless context && reason.is_a?(String)

    context.fetch('options').any? { |entry| entry.fetch('code') == reason }
  end

  def frozen_version(context)
    row = JrcContactCenter::EndingReasonVersion.where(account_id: @record.account_id).find(context.fetch('catalogue_id'))
    raise JrcContactCenter::OperationError, 'ending_reason_origin_unavailable' unless row.integrity_sha256 == context.fetch('integrity_sha256')

    row
  end

  def authorize!(context)
    account = Account.find(@record.account_id)
    member = account.account_users.find(@record.account_user_id)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: member, user: member.user }, :contact_center)
    raise Pundit::NotAuthorizedError unless member.user.reload.active_for_authentication? && policy.operate?

    native = JrcContactCenter::OrganizationalScope.new(account: account, account_user: member)
    return unless native.restricted?

    authorize_original_scope!(context, account, native)
  end

  def authorize_original_scope!(context, account, native)
    queue_id = context.fetch('queue_id')
    unit_id = context.fetch('unit_id')
    allowed = queue_id.present? || unit_id.present?
    allowed &&= native.units.exists?(id: unit_id) if unit_id
    allowed &&= JrcContactCenter::Queue.where(account: account, unit_id: native.units.select(:id)).exists?(id: queue_id) if queue_id
    raise ActiveRecord::RecordNotFound unless allowed
  end
end
