# frozen_string_literal: true

# Input for the existing AcwPolicy writer. Its caller retains current
# native configure/global-coverage authority and the account transaction/revision.
class JrcContactCenter::EndingActions::RuleInput
  FIELDS = %w[code name reason_code queue_id scope_revision timing active actions conditions].freeze

  def initialize(account:, member:)
    @account = account
    @member = account.account_users.find_by!(id: member.id, user_id: member.user_id)
  end

  def call(input)
    invalid! unless input.is_a?(Hash)

    row = input.deep_stringify_keys
    validate_header!(row)
    queue, scope = source_for!(row)
    validate_activation!(row, queue, scope)
    row.except('scope_revision').merge('queue_id' => queue.id.to_s, 'actions' => actions!(row), 'conditions' => conditions!(row),
                                       'scope' => scope_payload(scope, queue))
  end

  private

  def source_for!(row)
    queue = access.queues.lock('FOR SHARE').includes(:unit).find(identifier!(row.fetch('queue_id')))
    scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: queue.id).order(revision: :desc).first!
    raise JrcContactCenter::OperationError.new('ending_action_source_scope_changed', status: :conflict) if scope.unit_id != queue.unit_id

    JrcContactCenter::ConfigurationRevision.check_token!(scope.integrity_sha256, row.fetch('scope_revision'))
    [queue, scope]
  end

  def access
    JrcContactCenter::AccessScope.new(user_context: { account: @account, account_user: @member, user: @member.user })
  end

  def validate_header!(row)
    valid = row.keys.sort == input_fields(row).sort && text?(row['code'], 100) && text?(row['name'], 120)
    valid &&= text?(row['reason_code'], 100) && [true, false].include?(row['active'])
    valid &&= JrcContactCenter::EndingActions::RuleDefinition::TIMINGS.include?(row['timing'])
    invalid! unless valid
    validate_execution_mode!(row)
  end

  def input_fields(row)
    row.key?('execution_mode') ? FIELDS + ['execution_mode'] : FIELDS
  end

  def validate_execution_mode!(row)
    return unless row.key?('execution_mode')

    invalid! unless JrcContactCenter::EndingActions::RuleDefinition::EXECUTION_MODES.include?(row['execution_mode'])
  end

  def validate_activation!(row, queue, scope)
    catalogue = JrcContactCenter::AcwEndingReasons.new(account: @account).call
    reason = catalogue.fetch('entries').find { |entry| entry.fetch('code') == row.fetch('reason_code') }
    invalid! unless reason
    return unless row.fetch('active')

    invalid! unless reason.fetch('active')

    validate_active_source!(queue, scope, catalogue)
    JrcApprovals::Authorization.scope!(@account, scope.issuer_company_id, scope.business_unit_id)
  end

  def validate_active_source!(queue, scope, catalogue)
    valid = queue.status == 'active' && queue.unit.status == 'active' && scope.scope_state == 'mapped'
    invalid! unless valid && catalogue.fetch('required_queue_ids', []).include?(queue.id.to_s)
  end

  def actions!(row)
    entries = row.fetch('actions')
    invalid! unless entries.is_a?(Array) && entries.length <= 5
    invalid! if row.fetch('active') && entries.empty?
    result = entries.map { |entry| action!(entry, active: row.fetch('active')) }
    invalid! unless result.pluck('kind').uniq.length == result.length
    result
  end

  def action!(input, active:)
    invalid! unless input.is_a?(Hash)
    entry = input.deep_stringify_keys
    invalid! unless entry.keys.sort == %w[kind parameters]
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless entry['kind'] == 'project_task'

    validator = JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: @member)
    parameters = active ? validator.call(entry.fetch('parameters')) : validator.authorize_reference!(entry.fetch('parameters'))
    { 'kind' => 'project_task', 'parameters' => parameters }
  end

  # Mutable draft results never become an early call-end condition. No free-form
  # expression/eval, field coercion, message text or cross-record query is supported.
  def conditions!(row)
    input = row.fetch('conditions')
    invalid! unless input.is_a?(Hash) && input.keys == ['outcome_codes']
    codes = input.fetch('outcome_codes')
    validate_condition_codes!(codes)
    raise JrcContactCenter::OperationError, 'ending_action_conditions_require_completed_acw' if codes.any? && row.fetch('timing') != 'acw_completed'

    { 'outcome_codes' => codes.sort }
  end

  def validate_condition_codes!(codes)
    invalid! unless codes.is_a?(Array) && codes.length <= 10 && codes.all? { |code| text?(code, 100) }
    invalid! unless codes.uniq.length == codes.length
  end

  def scope_payload(scope, queue)
    { 'queue_scope_version_id' => scope.id.to_s, 'integrity_sha256' => scope.integrity_sha256,
      'unit_id' => queue.unit_id.to_s, 'issuer_company_id' => scope.issuer_company_id&.to_s,
      'business_unit_id' => scope.business_unit_id&.to_s }
  end

  def identifier!(value)
    valid = (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.valid_encoding? && value.to_s.match?(/\A[1-9][0-9]{0,18}\z/)
    invalid! unless valid && value.to_i <= 9_223_372_036_854_775_807
    value.to_s
  end

  def text?(value, maximum)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000") &&
      value.strip.present? && value == value.strip && value.length <= maximum
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_automation_rule'
  end
end
