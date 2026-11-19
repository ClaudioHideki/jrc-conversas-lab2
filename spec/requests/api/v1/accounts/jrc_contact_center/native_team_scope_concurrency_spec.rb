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
      JrcContactCenter::Qualification.where(account: account).destroy_all
      JrcContactCenter::AgentStateEvent.where(account: account).destroy_all
      JrcContactCenter::DailyFact.where(account: account).destroy_all
      JrcContactCenter::CallSession.where(account: account).destroy_all
      JrcContactCenter::QueueMembership.where(account: account).destroy_all
      JrcContactCenter::Queue.where(account: account).destroy_all
      JrcContactCenter::Unit.where(account: account).destroy_all
      account.jrc_crm_business_units.destroy_all
      account.master_companies.destroy_all
      account.destroy!
    end
  end

  # These helpers coordinate the real requests without replacing policies or locks.
  def hold_account_change(change, defer: false)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Account.find(account.id).with_lock do
          change.call unless defer
          state.fetch(:entered) << true
          Timeout.timeout(15) { state.fetch(:release).pop }
          change.call if defer
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
        state[:request_status] = session.response.status
        state[:request_body] = session.response.parsed_body
        results << state[:request_status]
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
  rescue Timeout::Error
    details = { completed_http_status: state[:request_status], expected_lock: 'Account FOR UPDATE', owned_synthetic_database: true }
    raise "Request did not reach the required account lock: #{details.to_json}"
  end

  def race_with_scope_change(change:, verb:, endpoint:, payload:, defer: false)
    hold_account_change(change, defer: defer)
    Timeout.timeout(8) { state.fetch(:entered).pop }
    dispatch_request(verb, endpoint, payload)
    wait_for_account_lock
    state.fetch(:release) << true
    Timeout.timeout(20) { workers.each(&:join) }
    expect(results.size).to eq(1)
    results.pop
  end

  %i[post patch delete].each do |verb|
    it "denies #{verb} after native user confirmation is revoked only once the real request is waiting" do
      team.add_members([recipient.id]) if verb == :delete
      original = team.team_members.pluck(:user_id)
      status = race_with_scope_change(
        change: -> { actor.update!(confirmed_at: nil) }, verb: verb,
        endpoint: "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
        payload: { user_ids: [recipient.id] }, defer: true
      )
      expect(actor.reload).not_to be_active_for_authentication
      expect(status).to eq(401)
      expect(team.team_members.reload.pluck(:user_id)).to eq(original)
    end
  end

  context 'when the last configured agent depends on native team membership' do
    before do
      peer = account.account_users.find_by!(user: recipient)
      peer.update!(custom_role: create(:custom_role, account: account, permissions: []))
      JrcContactCenter::AccessGrant.create!(account: account, account_user: peer, eligible: true)
      team.add_members([recipient.id])
      account.jrc_crm_user_business_units.create!(user: recipient, team: team, scope: 'GROUP', structure_managed: true)
      JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
    end

    it 'rechecks configuration authority after the real native roster request waits on the account mutex' do
      change = -> { account.account_users.find_by!(user: actor).custom_role.update!(permissions: ['jrc_contact_center_view']) }
      status = race_with_scope_change(
        change: change, verb: :delete, endpoint: "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members",
        payload: { user_ids: [recipient.id] }, defer: true
      )
      expect(status).to eq(401)
      expect(team.members).to include(recipient)
      expect(Audited.audit_class.where(auditable: queue, action: 'update')).to be_empty
    end

    it 'refuses a reviewed receipt after its queue revision changes during the actual SQL lock wait' do
      endpoint = "/api/v1/accounts/#{account.id}/teams/#{team.id}/team_members"
      delete endpoint, headers: headers, params: { user_ids: [recipient.id] }, as: :json
      expect(response).to have_http_status(:conflict)
      token = response.parsed_body.fetch('review').fetch('review_token')
      status = race_with_scope_change(
        change: -> { queue.update!(name: 'SYNTHETIC concurrent reviewed queue') }, verb: :delete, endpoint: endpoint,
        payload: { user_ids: [recipient.id], manager_confirmation: { confirmed: true, review_token: token } }, defer: true
      )
      expect(status).to eq(409)
      expect(team.members).to include(recipient)
      events = Audited.audit_class.where(auditable: queue, action: 'update')
      expect(events.filter_map { |event| event.audited_changes['manager_review'] }).to be_empty
    end
  end

  context 'when an owned pending qualification request is already waiting on the account mutex' do
    before do
      voice = JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                                    current_unit: unit, current_queue: queue, direction: 'inbound', status: 'ended',
                                                    started_at: 2.minutes.ago, answered_at: 90.seconds.ago, ended_at: 1.minute.ago)
      state[:qualification] = JrcContactCenter::Qualification.create!(
        account: account, account_user: account.account_users.find_by!(user: actor), call_session: voice,
        channel: 'voice', started_at: voice.ended_at, acw_limit_seconds: 180
      )
    end

    it 'denies a draft after operating permission is revoked during its verified SQL lock wait' do
      record = state.fetch(:qualification)
      status = race_with_scope_change(
        change: -> { account.account_users.find_by!(user: actor).custom_role.update!(permissions: ['jrc_contact_center_view']) },
        verb: :patch, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}/draft", defer: true,
        payload: { expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record),
                   qualification: { notes: 'SYNTHETIC forbidden late answer' } }
      )
      expect(status).to eq(401)
      expect(record.reload).to have_attributes(notes: nil, completed_at: nil)
      expect(Audited.audit_class.where(auditable: record, comment: JrcContactCenter::QualificationDraft::AUDIT_COMMENT)).to be_empty
    end

    it 'does not let a waiting draft replace the result completed while it was blocked' do
      record = state.fetch(:qualification)
      member = account.account_users.find_by!(user: actor)
      manager = JrcContactCenter::QualificationManager.new(account: account, member: member)
      change = -> { manager.complete!(record, reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC final') }
      status = race_with_scope_change(
        change: change, verb: :patch, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}/draft", defer: true,
        payload: { expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record),
                   qualification: { notes: 'SYNTHETIC obsolete draft' } }
      )
      expect(status).to eq(409)
      expect(record.reload.notes).to eq('SYNTHETIC final')
      expect(record.completed_at).to be_present
      expect(Audited.audit_class.where(auditable: record, comment: JrcContactCenter::QualificationDraft::AUDIT_COMMENT)).to be_empty
    end

    it 'rejects a waiting completion after a newer manual draft is committed during the actual SQL lock wait' do
      record = state.fetch(:qualification)
      member = account.account_users.find_by!(user: actor)
      token = JrcContactCenter::QualificationDraftRevision.token(record)
      service = JrcContactCenter::QualificationDraft.new(account: account, member: member)
      change = -> { service.save!(record, { notes: 'SYNTHETIC current answer' }, expected_revision: token) }
      status = race_with_scope_change(
        change: change, verb: :patch, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}", defer: true,
        payload: { expected_draft_revision: token,
                   qualification: { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC obsolete completion' } }
      )
      expect(status).to eq(409)
      expect(record.reload).to have_attributes(notes: 'SYNTHETIC current answer', completed_at: nil, duration_seconds: nil)
      expect(Audited.audit_class.where(auditable: record, comment: JrcContactCenter::QualificationDraft::AUDIT_COMMENT).count).to eq(1)
    end
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

  context 'when a whole native team deletion waits for current authority' do
    before do
      peer = account.account_users.find_by!(user: recipient)
      peer.update!(custom_role: create(:custom_role, account: account, permissions: []))
      team.add_members([recipient.id])
      JrcContactCenter::AccessGrant.create!(account: account, account_user: peer, eligible: true)
      JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
      account.jrc_crm_user_business_units.create!(user: recipient, scope: 'GROUP', structure_managed: true)
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
    end

    it 'denies a previously reviewed delete after the actor loses authentication during a real SQL wait' do
      endpoint = "/api/v1/accounts/#{account.id}/teams/#{team.id}"
      delete endpoint, headers: headers, as: :json
      token = response.parsed_body.fetch('review').fetch('review_token')
      status = race_with_scope_change(
        change: -> { actor.update!(confirmed_at: nil) }, verb: :delete, endpoint: endpoint,
        payload: { manager_confirmation: { confirmed: true, review_token: token } }, defer: true
      )
      expect(status).to eq(401)
      expect(account.teams.exists?(team.id)).to be(true)
      expect(team.members).to include(recipient)
    end

    it 'rejects an old-team revision only after acquiring the native Account SQL lock' do
      endpoint = "/api/v1/accounts/#{account.id}/teams/#{team.id}"
      delete endpoint, headers: headers, as: :json
      token = response.parsed_body.fetch('review').fetch('review_token')
      status = race_with_scope_change(
        change: -> { team.update!(name: 'SYNTHETIC changed during wait') }, verb: :delete, endpoint: endpoint,
        payload: { manager_confirmation: { confirmed: true, review_token: token } }, defer: true
      )
      expect(status).to eq(409)
      expect(team.reload.name).to eq('SYNTHETIC changed during wait')
      expect(team.members).to include(recipient)
    end

    it 'waits for the native Team row before comparing its revision with the manager receipt' do
      endpoint = "/api/v1/accounts/#{account.id}/teams/#{team.id}"
      delete endpoint, headers: headers, as: :json
      token = response.parsed_body.fetch('review').fetch('review_token')
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          row = Team.find(team.id)
          row.with_lock do
            state.fetch(:entered) << true
            Timeout.timeout(15) { state.fetch(:release).pop }
            row.update!(name: 'SYNTHETIC changed under Team row lock')
          end
        end
      rescue StandardError => e
        results << e
      end
      Timeout.timeout(8) { state.fetch(:entered).pop }
      payload = { manager_confirmation: { confirmed: true, review_token: token } }
      dispatch_request(:delete, endpoint, payload)
      Timeout.timeout(8) do
        connection = ActiveRecord::Base.connection
        loop do
          pid = connection.quote(state[:request_pid])
          sql = "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = #{pid} AND wait_event_type = 'Lock' " \
                "AND query LIKE '%teams%' AND query LIKE '%FOR UPDATE%')"
          break if connection.uncached { connection.select_value(sql) }

          sleep 0.02
        end
      end
      state.fetch(:release) << true
      Timeout.timeout(20) { workers.each(&:join) }
      expect(results.size).to eq(1)
      expect(results.pop).to eq(409)
      expect(state.fetch(:request_body).fetch('error')).to eq('team_deletion_confirmation_required')
      expect(team.reload.name).to eq('SYNTHETIC changed under Team row lock')
      expect(team.members).to include(recipient)
    end
  end
end
