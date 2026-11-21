# frozen_string_literal: true

# Permission and scope are reloaded inside the existing native Account mutex for every mutation.
class JrcContactCenter::CalendarCatalog
  def initialize(context:, unit_id:)
    @context = context.slice(:account, :account_user, :user)
    @unit_id = JrcServiceDesk::Input.id(unit_id)
    refresh!
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_unit'
  end

  def call
    refresh!
    state = catalog.call
    state.merge('unit_id' => @unit.id.to_s, 'unit_name' => @unit.name, 'unit_timezone' => @unit.timezone,
                'revision' => revision, 'local_only' => true, 'pabx_confirmed' => false)
  end

  def find!(id)
    state = call
    state.fetch('entries').find { |row| row.fetch('id') == id } || raise(ActiveRecord::RecordNotFound)
  end

  def save!(input, expected_revision:, create: false)
    account = @context.fetch(:account)
    JrcContactCenter::AuthorityTransaction.call(account: account, member: @context.fetch(:account_user)) do
      write_entry!(input, expected_revision: expected_revision, create: create)
      { 'item' => find!(input.fetch('id')), 'revision' => revision, 'unit_id' => @unit.id.to_s,
        'local_only' => true, 'pabx_confirmed' => false }
    end
  end

  def preview(id, date:)
    item = find!(id)
    result = JrcContactCenter::CalendarDefinition.new(item.fetch('definition')).preview(date)
    result.merge('calendar_id' => id, 'active' => item.fetch('active'), 'unit_id' => @unit.id.to_s,
                 'name' => item.fetch('definition').fetch('name'), 'revision' => revision)
  end

  private

  def write_entry!(input, expected_revision:, create:)
    refresh!
    before = catalog.call
    rows = before.fetch('entries')
    entry = normalize(input)
    current = rows.find { |row| row.fetch('id') == entry.fetch('id') }
    return if create && current == entry

    check_identity!(create, current)
    JrcContactCenter::ConfigurationRevision.check_token!(revision, expected_revision)
    return if current == entry

    updated = current ? rows.map { |row| row.fetch('id') == entry.fetch('id') ? entry : row } : rows + [entry]
    persist!(before.merge('entries' => updated, 'version' => before.fetch('version') + 1))
  end

  def check_identity!(create, current)
    raise ActiveRecord::RecordNotFound unless create || current
    raise JrcContactCenter::OperationError.new('calendar_identity_conflict', status: :conflict) if create && current
  end

  def catalog
    JrcContactCenter::CalendarCatalogState.new(unit: @unit)
  end

  def revision
    JrcContactCenter::ConfigurationRevision.token(@unit)
  end

  def refresh!
    @context.each_value(&:reload)
    raise Pundit::NotAuthorizedError unless @context.fetch(:account).active? && @context.fetch(:user).active_for_authentication?

    access = JrcContactCenter::AccessScope.new(user_context: @context)
    raise Pundit::NotAuthorizedError unless access.policy.configure?

    @unit = access.units.find(@unit_id)
  end

  def normalize(input)
    valid = input.is_a?(Hash) && input.keys.all?(String) && input.keys.sort == %w[active definition id]
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_catalog' unless valid

    value = input.merge('definition' => JrcContactCenter::CalendarDefinition.new(input.fetch('definition')).values)
    catalog.entry!(value)
  end

  def persist!(state)
    catalog.validate!(state)
    settings = @unit.settings.merge(JrcContactCenter::CalendarCatalogState::KEY => state)
    @unit.update!(settings: settings)
    @unit.reload
  end
end
