# Administrative navigation uses actual local sources only. Pending provider
# capabilities never become enabled buttons or synthetic counters.
class JrcContactCenter::Administration
  CARDS = {
    'numbers' => %i[administer pending_contract], 'extensions' => %i[administer read_only],
    'queues' => %i[configure available], 'ivr' => %i[publish pending_contract],
    'hours' => %i[configure pending_contract], 'audio' => %i[configure pending_contract],
    'pauses' => %i[configure pending_contract], 'closures' => %i[configure available],
    'distribution' => %i[configure pending_contract], 'permissions' => %i[administer native_module],
    'recordings' => %i[recordings_view pending_contract], 'pabx' => %i[administer read_only],
    'approvals' => %i[approve native_module], 'general' => %i[configure available],
    'integrations' => %i[audit read_only]
  }.freeze

  def initialize(context:, access:)
    @context = context
    @access = access
    @account = access.account
    @policy = access.policy
  end

  def call
    {
      observed_at: Time.current,
      cards: cards, capabilities: capabilities, native_links: native_links, provider: provider_state,
      units: @access.units.order(:name, :id).map { |unit| { id: unit.id, name: unit.name } },
      queues: @access.queues.order(:name, :id).map { |queue| { id: queue.id, name: queue.name } },
      corporate: corporate_options, pause_catalog: pause_catalog_metadata
    }
  end

  def authorize_section!(key)
    permission = { 'audit' => :audit, 'teams' => :configure, 'events' => :control }.fetch(key) do
      CARDS.fetch(key) { raise ActiveRecord::RecordNotFound }.first
    end
    raise Pundit::NotAuthorizedError unless card_allowed?(key, permission)
  end

  private

  def cards
    CARDS.filter_map do |key, (permission, state)|
      next unless card_allowed?(key, permission)

      { key: key, state: state, count: count_for(key) }
    end
  end

  # Local draft configuration is independent of provider publication authority.
  def card_allowed?(key, permission)
    @policy.public_send("#{permission}?") || (key == 'ivr' && @policy.configure?)
  end

  def capabilities
    actions = %w[configure administer audit publish approve reports recordings_view recordings_listen recordings_download monitor]
    actions.index_with { |key| @policy.public_send("#{key}?") }
           .merge('control' => @policy.control?, 'configuration_global' => global_configuration?,
                  'configuration_audit' => @policy.audit? && @account.feature_enabled?('audit_logs'))
  end

  def global_configuration?
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @context.fetch(:user))
    @policy.configure? && (!coverage.configured? || coverage.group?)
  end

  def native_links
    { permissions: native_roles_available?, role_editor: native_role_editor_available?, access_editor: native_access_editor_available?,
      pabx_settings: @policy.administer? && @context.fetch(:user).is_a?(SuperAdmin) && @context.fetch(:account_user).administrator?,
      approvals: @account.feature_enabled?('jrc_approvals') &&
        JrcCrm::CurrentStructureScopes.new(account: @account, user: @context.fetch(:user)).call.exists? }
  end

  def native_roles_available?
    @account.feature_enabled?('custom_roles') && @context.fetch(:account_user).administrator?
  end

  def native_role_editor_available?
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @context.fetch(:user))
    native_roles_available? && (!coverage.configured? || coverage.group?)
  end

  def native_access_editor_available?
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @context.fetch(:user))
    @policy.administer? && @context.fetch(:account_user).administrator? && (!coverage.configured? || coverage.group?)
  end

  def provider_state
    integration = @account.telephony_integration
    { state: 'pending_contract', configured: integration.present? && Pabx::Settings.new(integration).configured?,
      last_sync_at: integration&.pabx_sync_state&.fetch('last_success_at', nil),
      last_error: integration&.pabx_sync_state&.fetch('last_error', nil).present? }
  end

  def count_for(key)
    return @access.queues.count if key == 'queues'
    return @access.units.count if key == 'general'
    if key == 'closures'
      return JrcContactCenter::Qualification.pending.where(account: @account, call_session_id: @access.call_sessions.select(:id)).count
    end

    nil
  end

  def pause_catalog_metadata
    return { role_options: [] } unless global_configuration? && native_role_editor_available?

    roles = CustomRole.where(account: @account).order(:name, :id).pluck(:id, :name)
    { role_options: roles.map { |id, name| { id: id.to_s, name: name } } }
  end

  def corporate_options
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @context.fetch(:user))
    { companies: @account.master_companies.where(id: coverage.company_ids).order(:name).map { |row| { id: row.id, name: row.name } },
      units: @account.jrc_crm_business_units.where(id: coverage.unit_ids).order(:name).map do |row|
        { id: row.id, name: row.name, company_id: row.company_id }
      end }
  end
end
