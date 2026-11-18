require 'rails_helper'
require 'timeout'

RSpec.describe 'Current corporate team authority after a real account lock wait', type: :request do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:recipient) { create(:user, account: account) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:business_unit) { account.jrc_crm_business_units.create!(name: 'SYNTHETIC unit', code: 'A', operating_company: company) }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'A', name: 'SYNTHETIC operational unit', kind: 'sac',
                                   settings: { issuer_company_id: company.id, business_unit_id: business_unit.id })
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q', name: 'Original') }
  let(:team) { create(:team, account: account) }
  let(:team_scope) { account.jrc_crm_team_scopes.create!(team: team, scope: 'GROUP') }
  let(:group) { account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true) }
  let(:workers) { [] }
  let(:results) { Queue.new }
  let(:state) { {} }

  before do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?

    state[:entered] = Queue.new
    state[:release] = Queue.new
    state[:ready] = true
    account.enable_features!('jrc_contact_center', 'jrc_crm', 'custom_roles', 'audit_logs')
    role = create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS + ['jrc_crm'])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    headers
    group
    queue
    team_scope
  end

  after do
    if state[:ready]
      state.fetch(:release) << true
      workers.each { |thread| thread.join(20) }
      raise 'Synthetic request still active' if workers.any?(&:alive?)

      account.jrc_crm_user_business_units.destroy_all
      account.jrc_crm_team_scopes.destroy_all
      account.teams.destroy_all
      JrcContactCenter::CallSession.where(account: account).destroy_all
      JrcContactCenter::Queue.where(account: account).destroy_all
      JrcContactCenter::Unit.where(account: account).destroy_all
      account.jrc_crm_business_units.destroy_all
      account.master_companies.destroy_all
      account.destroy!
    end
  end

  # These helpers coordinate the real requests without replacing policies or locks.
  def hold_account_change(change)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Account.find(account.id).with_lock do
          change.call
          state.fetch(:entered) << true
          Timeout.timeout(15) { state.fetch(:release).pop }
        end
      end
    rescue StandardError => e
      results << e
    end
  end

  def dispatch_request(verb, endpoint, payload)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        state[:request_pid] = ActiveRecord::Base.connection.raw_connection.backend_pid
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.public_send(verb, endpoint, headers: headers, params: payload, as: :json)
        results << session.response.status
      end
    rescue StandardError => e
      results << e
    end
  end

  def wait_for_account_lock
    Timeout.timeout(8) do
      connection = ActiveRecord::Base.connection
      loop do
        pid = connection.quote(state[:request_pid])
        sql = "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = #{pid} AND wait_event_type = 'Lock' " \
              "AND query LIKE '%accounts%' AND query LIKE '%FOR UPDATE%')"
        break if connection.uncached { connection.select_value(sql) }

        sleep 0.02
      end
    end
  end

  def race_with_scope_change(change:, verb:, endpoint:, payload:)
    hold_account_change(change)
    Timeout.timeout(8) { state.fetch(:entered).pop }
    dispatch_request(verb, endpoint, payload)
    wait_for_account_lock
    state.fetch(:release) << true
    Timeout.timeout(20) { workers.each(&:join) }
    expect(results.size).to eq(1)
    results.pop
  end

  it 'does not reinclude a user after the actor loses Group during the membership lock wait' do
    team.add_members([recipient.id])
    source = account.jrc_crm_user_business_units.create!(user: recipient, team: team, scope: 'GROUP', structure_managed: true)
    team.remove_members([recipient.id])
    status = race_with_scope_change(
      change: -> { group.update!(active: false) }, verb: :post,
      endpoint: "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members", payload: { user_ids: [recipient.id] }
    )
    expect(status).to eq(401)
    expect(TeamMember.where(team_id: team.id)).to be_empty
    expect(source.reload).to be_active
    expect(JrcCrm::CorporateCoverage.new(account: account, user: recipient)).not_to be_group
  end

  it 'rechecks native scope administration after the same Group source is revoked during the lock wait' do
    status = race_with_scope_change(
      change: -> { group.update!(active: false) }, verb: :post,
      endpoint: "/api/v1/accounts/#{account.id}/crm/organization_structure/user_scopes",
      payload: { user_scope: { user_id: recipient.id, scope: 'GROUP' } }
    )
    expect(status).to eq(401)
    expect(account.jrc_crm_user_business_units.where(user: recipient)).to be_empty
    expect(group.reload).not_to be_active
  end

  it 'denies a Call Center write after its inherited team coverage is revoked during the account lock wait' do
    team.add_members([actor.id])
    source = account.jrc_crm_user_business_units.create!(user: actor, team: team, scope: 'GROUP', structure_managed: true)
    group.destroy!
    status = race_with_scope_change(
      change: -> { team_scope.update!(active: false) }, verb: :patch,
      endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}",
      payload: { queue: { name: 'Forbidden stale write' }, expected_revision: JrcContactCenter::ConfigurationRevision.token(queue) }
    )
    expect(status).to eq(404)
    expect(queue.reload.name).to eq('Original')
    expect(source.reload).to be_active
    expect(Audited.audit_class.where(auditable: queue, action: 'update')).to be_empty
  end

  %w[eligibility profile].each do |authority|
    it "does not save a call observation after #{authority} is revoked during the account lock wait" do
      voice = JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                                    current_unit: unit, current_queue: queue, direction: 'inbound',
                                                    status: 'connected', started_at: Time.current)
      original = voice.attributes
      change = lambda do
        member = account.account_users.find_by!(user: actor)
        if authority == 'eligibility'
          JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
        else
          member.custom_role.update!(permissions: ['jrc_contact_center_view'])
        end
      end
      status = race_with_scope_change(
        change: change, verb: :patch,
        endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions/#{voice.id}/observations",
        payload: { observations: { text: 'Forbidden stale note', lock_version: voice.lock_version } }
      )
      expect(status).to eq(401)
      expect(voice.reload.attributes).to eq(original)
      expect(JrcContactCenter::CallObservation.where(call_session: voice)).to be_empty
    end
  end

  it 'does not save a call observation after inherited team scope is revoked during the account lock wait' do
    team.add_members([actor.id])
    source = account.jrc_crm_user_business_units.create!(user: actor, team: team, scope: 'GROUP', structure_managed: true)
    group.destroy!
    voice = JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                                  current_unit: unit, current_queue: queue, direction: 'inbound',
                                                  status: 'connected', started_at: Time.current)
    original = voice.attributes
    status = race_with_scope_change(
      change: -> { team_scope.update!(active: false) }, verb: :patch,
      endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/call_sessions/#{voice.id}/observations",
      payload: { observations: { text: 'Forbidden stale note', lock_version: voice.lock_version } }
    )
    expect(status).to eq(404)
    expect(voice.reload.attributes).to eq(original)
    expect(JrcContactCenter::CallObservation.where(call_session: voice)).to be_empty
    expect(source.reload).to be_active
  end
end
