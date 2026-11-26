# frozen_string_literal: true

class JrcContactCenter::EndingActions::VisibleRules
  FILTERS = %w[q status reason_code rule_code page per_page].freeze

  def initialize(account:, member:, filters: {})
    @account = account
    @context = JrcContactCenter::EndingActions::ConfigurationContext.new(account: account, member: member, for_rule: true)
    @filters = validate_filters!(filters)
  end

  def call
    @context.call do |member|
      catalogue = JrcContactCenter::EndingActions::Catalogue.new(account: @account)
      catalogue.verify_synchronized!
      rows = catalogue.call.fetch('entries').select { |row| visible?(row, member) }
      paginate(rows.select { |row| matching?(row) }, member)
    end
  end

  private

  def visible?(rule, member)
    # Current source coverage and each destination policy are independent.
    # Stored IDs and private text never grant access after revocation.
    JrcContactCenter::EndingActions::RuleSourceAuthority.new(account: @account, member: member).call(rule)
    rule.fetch('actions').each do |action|
      if rule.fetch('destination_schema_version', 1) == 2
        JrcContactCenter::EndingActions::ConfiguredNativeAction.new(
          account: @account, member: member, source_scope: rule.fetch('scope')
        ).call(action, active: false)
      else
        raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action.fetch('kind') == 'project_task'

        JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: member).authorize_reference!(action.fetch('parameters'))
      end
    end
    true
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    false
  rescue JrcContactCenter::OperationError => error
    raise unless %w[ending_service_desk_mapping_required ending_service_desk_mapping_changed].include?(error.code)

    false
  end

  def matching?(row)
    return false if @filters['rule_code'].present? && row.fetch('code') != @filters['rule_code']

    return false unless status_matches?(row)
    return false if @filters['reason_code'].present? && row.fetch('reason_code') != @filters['reason_code']

    query_matches?(row)
  end

  def status_matches?(row)
    status = @filters.fetch('status', 'all')
    status == 'all' || row.fetch('active') == (status == 'active')
  end

  def query_matches?(row)
    query = @filters.fetch('q', '').strip.downcase
    query.empty? || [row.fetch('code'), row.fetch('name'), row.fetch('reason_code')].any? { |value| value.downcase.include?(query) }
  end

  def paginate(rows, member)
    page = integer_filter('page', 1, 1_000_000)
    size = integer_filter('per_page', 20, 50)
    ordered = rows.sort_by { |row| [row.fetch('name'), row.fetch('code')] }
    revision = JrcContactCenter::AcwPolicy.new(account: @account).revision
    selected = ordered.slice((page - 1) * size, size) || []
    { items: selected, destination_presentations: destination_presentations(selected, member),
      meta: { page: page, per_page: size, total: rows.length, pages: (rows.length.to_f / size).ceil },
      revision: revision, editor_context: editor_context(revision, member),
      execution_available: false, configuration_only: true }
  end

  def destination_presentations(rows, member)
    context = { account: @account, account_user: member, user: member.user }
    rows.each_with_object({}) do |rule, result|
      action = rule.fetch('actions').find { |row| row.fetch('kind') == 'service_desk' }
      next unless action

      reader = JrcContactCenter::EndingActions::ServiceDeskRuleParameters.new(user_context: context, source_scope: rule.fetch('scope'))
      result[rule.fetch('code')] = { service_desk: reader.presentation(action.fetch('parameters')) }
    end
  end

  # The shared native reason catalogue is already selectable by agents in their
  # own attendance. Do not expose global ACW settings, foreign queue IDs or notes.
  def editor_context(revision, member)
    catalogue = JrcContactCenter::AcwEndingReasons.new(account: @account).call
    entries = catalogue.fetch('entries').sort_by { |row| [row.fetch('order'), row.fetch('code')] }
    { id: @account.id.to_s, revision: revision,
      voice_reason_catalog: { version: catalogue.fetch('version'), entries: entries.map { |row| row.slice('code', 'name', 'active') } },
      destination_options: destination_options(member) }
  end

  def destination_options(member)
    allowed = JrcContactCenter::EndingActions::ConfiguredNativeAction.crm_available?(member)
    { crm: { configuration_available: allowed, activity_types: allowed ? JrcCrm::Activity::ACTIVITY_TYPES : [] } }
  end

  def validate_filters!(input)
    invalid! unless input.is_a?(Hash)

    values = input.stringify_keys
    invalid! unless (values.keys - FILTERS).empty?
    validate_text_filters!(values)
    invalid! if values.key?('status') && %w[all active inactive].exclude?(values['status'])
    values
  end

  def validate_text_filters!(values)
    %w[q reason_code rule_code].each do |key|
      next unless values.key?(key)

      invalid! unless valid_filter_text?(values[key])
    end
  end

  def valid_filter_text?(value)
    value.is_a?(String) && value.valid_encoding? && value.exclude?("\u0000") && value.length <= 100
  end

  def integer_filter(key, fallback, maximum)
    value = @filters.fetch(key, fallback)
    typed = value.is_a?(Integer) || (value.is_a?(String) && value.valid_encoding? && value.match?(/\A[1-9][0-9]{0,6}\z/))
    invalid! unless typed && value.to_i.between?(1, maximum)

    value.to_i
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_ending_rule_filters'
  end
end
