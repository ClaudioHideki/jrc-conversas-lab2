require 'digest'

# Account-local catalog for the existing native pause transition. No PABX publication.
class JrcContactCenter::PauseCatalog
  KEY = 'jrc_contact_center_pause_catalog'
  MAX_ENTRIES = 100

  def initialize(account:)
    @account = account
  end

  def call
    state = stored.deep_dup
    state.merge('id' => @account.id.to_s, 'revision' => revision, 'local_only' => true)
  end

  def revision
    state = stored
    rows = state.fetch('entries').map { |row| JrcContactCenter::PauseReasonDefinition::FIELDS.map { |field| row[field] } }
    Digest::SHA256.hexdigest([KEY, @account.id, state.fetch('version'), state.fetch('enforced'), rows].to_json)
  end

  def update!(attributes, expected_revision:, activation_confirmed: false)
    @account.with_lock do
      JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision)
      previous = stored
      values = validate_values(attributes)
      if !previous.fetch('enforced') && values.fetch('enforced') && activation_confirmed != true
        raise JrcContactCenter::OperationError, 'pause_activation_confirmation_required'
      end
      return call if previous.slice('enforced', 'entries') == values

      current = values.merge('version' => previous.fetch('version') + 1)
      @account.update!(settings: @account.settings.merge(KEY => current))
      JrcContactCenter::PauseCatalogAudit.write!(account: @account, before: previous, after: current)
    end
    call
  end

  def enforced?
    stored.fetch('enforced')
  end

  def options(member:, memberships:)
    memberships = authorized_memberships(member, memberships)
    state = stored
    queue_units = memberships.joins(:queue).distinct.pluck(:queue_id, 'jrc_contact_center_queues.unit_id').to_h
    rows = applicable_entries(member, memberships).map { |entry| operator_option(entry, queue_units) }
    { enforced: state.fetch('enforced'), revision: revision, local_only: true, entries: rows }
  end

  def selection(code, member:, memberships:)
    memberships = authorized_memberships(member, memberships)
    entry = applicable_entries(member, memberships).find { |row| row.fetch('code') == code }
    raise JrcContactCenter::OperationError, 'pause_reason_not_allowed' if stored.fetch('enforced') && !entry
    return unless entry

    public_entry(entry).merge(entry.slice('unit_ids', 'custom_role_ids')).merge('revision' => revision, 'version' => stored.fetch('version'))
  end

  private

  def stored
    return { 'version' => 0, 'enforced' => false, 'entries' => [] } unless @account.settings.key?(KEY)

    value = @account.settings.fetch(KEY)
    valid = valid_stored_header?(value) && valid_stored_entries?(value.fetch('entries'))
    raise JrcContactCenter::OperationError, 'invalid_pause_catalog_configuration' unless valid

    value
  end

  def valid_stored_header?(value)
    value.is_a?(Hash) && value.keys.sort == %w[enforced entries version] &&
      valid_version?(value['version']) && [true, false].include?(value['enforced']) && valid_entry_collection?(value['entries'])
  end

  def valid_version?(version)
    version.is_a?(Integer) && version.positive?
  end

  def valid_stored_entries?(entries)
    validator = JrcContactCenter::PauseReasonDefinition.new(account: @account)
    codes = entries.filter_map do |row|
      return false unless row.is_a?(Hash) && row.keys.sort == JrcContactCenter::PauseReasonDefinition::FIELDS.sort
      return false unless validator.call(row, verify_references: false) == row

      row['code']
    end
    codes.uniq.length == codes.length
  rescue JrcContactCenter::PauseReasonDefinition::Invalid
    false
  end

  def validate_values(input)
    data = input_values(input)

    validator = JrcContactCenter::PauseReasonDefinition.new(account: @account)
    entries = data.fetch('entries').map { |row| validator.call(row) }
    codes = entries.pluck('code')
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['code'] unless codes.uniq.length == codes.length
    raise JrcContactCenter::OperationError, 'active_pause_reason_required' if data['enforced'] && entries.none? { |row| row['active'] }

    { 'enforced' => data.fetch('enforced'), 'entries' => entries }
  end

  def input_values(input)
    valid = input.is_a?(Hash) && input.keys.map(&:to_s).sort == %w[enforced entries]
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['entries'] unless valid

    data = input.deep_stringify_keys
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['enforced'] unless [true, false].include?(data['enforced'])
    raise JrcContactCenter::PauseReasonDefinition::Invalid, ['entries'] unless valid_entry_collection?(data['entries'])

    data
  end

  def valid_entry_collection?(entries)
    entries.is_a?(Array) && entries.length <= MAX_ENTRIES && entries.to_json.bytesize <= 262_144
  end

  def authorized_memberships(member, memberships)
    raise Pundit::NotAuthorizedError unless member&.account_id == @account.id

    context = { account: @account, account_user: member, user: member.user }
    raise Pundit::NotAuthorizedError unless JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?

    native = JrcContactCenter::AgentStateSnapshot.new(account_user: member).memberships
    native.where(id: memberships.select(:id))
  end

  def applicable_entries(member, memberships)
    units = memberships.joins(:queue).distinct.pluck('jrc_contact_center_queues.unit_id')
    stored.fetch('entries').select do |entry|
      entry.fetch('active') && JrcContactCenter::PauseReasonDefinition.applicable?(entry, member: member, unit_ids: units)
    end
  end

  def operator_option(entry, queue_units)
    units = entry.fetch('unit_ids')
    ids = queue_units.filter_map { |id, unit| id.to_s if units.empty? || units.include?(unit) }
    public_entry(entry).merge('scope_queue_ids' => ids, 'all_queues' => units.empty?)
  end

  def public_entry(entry)
    entry.slice('code', 'name', 'category', 'description', *JrcContactCenter::PauseReasonDefinition::TIMES).deep_dup
  end
end
