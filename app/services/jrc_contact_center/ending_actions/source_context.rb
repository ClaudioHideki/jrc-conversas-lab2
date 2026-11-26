# frozen_string_literal: true

class JrcContactCenter::EndingActions::SourceContext
  def initialize(account:, member:, queue_id:)
    @account = account
    @context = JrcContactCenter::EndingActions::ConfigurationContext.new(account: account, member: member, for_rule: true)
    @queue_id = identifier!(queue_id)
  end

  def call
    @context.call do |member|
      queue, row = source_records(member)
      present(queue, row)
    end
  end

  private

  def source_records(member)
    context = { account: @account, account_user: member, user: member.user }
    access = JrcContactCenter::AccessScope.new(user_context: context)
    queue = access.queues.lock('FOR SHARE').includes(:unit).find(@queue_id)
    row = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: queue.id).order(revision: :desc).first!
    raise JrcContactCenter::OperationError.new('ending_action_source_scope_changed', status: :conflict) unless row.unit_id == queue.unit_id

    [queue, row]
  end

  def present(queue, row)
    catalogue = JrcContactCenter::AcwEndingReasons.new(account: @account).call
    registered = catalogue.fetch('required_queue_ids', []).include?(queue.id.to_s)
    { id: queue.id.to_s, name: queue.name, unit: { id: queue.unit.id.to_s, name: queue.unit.name },
      scope_revision: row.integrity_sha256, scope_state: row.scope_state, registered_reason_required: registered,
      configuration_available: registered && row.scope_state == 'mapped' && queue.status == 'active' && queue.unit.status == 'active',
      execution_available: false }
  end

  def identifier!(value)
    valid = (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.valid_encoding? && value.to_s.match?(/\A[1-9][0-9]{0,18}\z/)
    raise JrcContactCenter::OperationError, 'invalid_ending_rule_source' unless valid && value.to_i <= 9_223_372_036_854_775_807

    value.to_s
  end
end
