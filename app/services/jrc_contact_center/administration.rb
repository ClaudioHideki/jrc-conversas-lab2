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
    integration = @account.telephony_integration
    {
      observed_at: Time.current,
      cards: CARDS.filter_map do |key, (permission, state)|
        next unless @policy.public_send("#{permission}?")

        { key: key, state: state, count: count_for(key) }
      end,
      capabilities: %w[configure administer audit publish approve recordings_view recordings_listen recordings_download monitor]
                    .index_with { |key| @policy.public_send("#{key}?") }.merge('control' => @policy.control?),
      native_links: {
        permissions: @account.feature_enabled?('custom_roles') && @context.fetch(:account_user).administrator?,
        approvals: @account.feature_enabled?('jrc_approvals') &&
          JrcCrm::UserBusinessUnit.structure_managed.active.exists?(account: @account, user: @context.fetch(:user))
      },
      provider: { state: 'pending_contract', last_sync_at: integration&.pabx_sync_state&.fetch('last_success_at', nil),
                  last_error: integration&.pabx_sync_state&.fetch('last_error', nil).present? },
      units: @access.units.order(:name, :id).map { |unit| { id: unit.id, name: unit.name } },
      queues: @access.queues.order(:name, :id).map { |queue| { id: queue.id, name: queue.name } },
      corporate: corporate_options
    }
  end

  def authorize_section!(key)
    permission = { 'audit' => :audit, 'teams' => :configure, 'events' => :control }.fetch(key) do
      CARDS.fetch(key) { raise ActiveRecord::RecordNotFound }.first
    end
    raise Pundit::NotAuthorizedError unless @policy.public_send("#{permission}?")
  end

  private

  def count_for(key)
    return @access.queues.count if key == 'queues'
    return @access.units.count if key == 'general'
    return JrcContactCenter::Qualification.pending.where(account: @account, call_session_id: @access.call_sessions.select(:id)).count if key == 'closures'

    nil
  end

  def corporate_options
    coverage = JrcCrm::CorporateCoverage.new(account: @account, user: @context.fetch(:user))
    { companies: @account.master_companies.where(id: coverage.company_ids).order(:name).map { |row| { id: row.id, name: row.name } },
      units: @account.jrc_crm_business_units.where(id: coverage.unit_ids).order(:name).map { |row| { id: row.id, name: row.name, company_id: row.company_id } } }
  end
end
