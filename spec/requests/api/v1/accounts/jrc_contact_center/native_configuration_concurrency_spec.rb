require 'rails_helper'
require 'timeout'

RSpec.describe 'Call Center concurrent configuration boundaries', type: :request do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC #{code}")
    end
  end
  let(:units) do
    business_units.map do |business_unit|
      JrcContactCenter::Unit.create!(
        account: account, code: business_unit.code, name: business_unit.name, kind: 'sac',
        settings: { issuer_company_id: company.id, business_unit_id: business_unit.id }
      )
    end
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: units.first, code: 'Q', name: 'Original') }
  let(:workers) { [] }
  let(:entered) { Queue.new }
  let(:read) { Queue.new }
  let(:release) { Queue.new }
  let(:results) { Queue.new }
  let(:subscriptions) { [] }
  let(:state) { {} }

  before do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?

    state[:ready] = true
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    headers
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(
      account: account, user: actor, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
      company: company, active: true, structure_managed: true
    )
    queue
  end

  after do
    if state[:ready]
      release << true
      workers.each { |thread| thread.join(20) }
      raise 'Synthetic request still active' if workers.any?(&:alive?)

      subscriptions.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
      # Only fixtures belonging to this guarded disposable suite's Account.
      JrcContactCenter::RoutingRule.where(account: account).destroy_all
      JrcContactCenter::Qualification.where(account: account).destroy_all
      JrcContactCenter::AgentStateEvent.where(account: account).destroy_all
      JrcContactCenter::CallLeg.where(account: account).destroy_all
      JrcContactCenter::CallSession.where(account: account).destroy_all
      JrcContactCenter::Callback.where(account: account).destroy_all
      JrcContactCenter::CaseEvent.where(account: account).destroy_all
      JrcContactCenter::Case.where(account: account).destroy_all
      JrcContactCenter::QueueMembership.where(account: account).destroy_all
      JrcContactCenter::Queue.where(account: account).destroy_all
      JrcContactCenter::AudioFolder.where(account: account).delete_all
      JrcContactCenter::Unit.where(account: account).destroy_all
      JrcCrm::UserBusinessUnit.where(account: account).destroy_all
      JrcCrm::BusinessUnit.where(account: account).destroy_all
      account.master_companies.destroy_all
      account.destroy!
    end
  end

  # The same barriers coordinate both real HTTP races; no timing sleeps.
  def observe_queue_read(target_id)
    subscriptions << ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
      sql = event.payload[:sql]
      next unless Thread.current[:cc_configuration_request] && native_queue_select?(sql)
      next unless event.payload[:binds].any? { |bind| bind.name == 'id' && bind.value_for_database == target_id }

      read << true
    end
  end

  def native_queue_select?(sql)
    sql.start_with?('SELECT') && sql.include?('"jrc_contact_center_queues"') && !sql.match?(/FOR (?:NO KEY )?UPDATE/)
  end

  def hold_queue_change(change)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        target = JrcContactCenter::Queue.find(queue.id)
        target.with_lock do
          target.update!(change)
          entered << true
          Timeout.timeout(15) { release.pop }
        end
      end
    rescue StandardError => e
      results << e
    end
  end

  def dispatch_configuration_request(verb, endpoint, payload)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Thread.current[:cc_configuration_request] = true
        state[:request_pid] = ActiveRecord::Base.connection.raw_connection.backend_pid
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.public_send(verb, endpoint, headers: headers, params: payload, as: :json)
        results << session.response.status
      end
    rescue StandardError => e
      results << e
    end
  end

  def race_with_queue_change(change:, verb:, endpoint:, payload:)
    observe_queue_read(queue.id)
    hold_queue_change(change)
    Timeout.timeout(8) { entered.pop }
    dispatch_configuration_request(verb, endpoint, payload)
    Timeout.timeout(8) { read.pop }
    state[:before_release]&.call
    release << true
    Timeout.timeout(20) { workers.each(&:join) }
    results.pop
  end

  def observe_account_read
    subscriptions << ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
      sql = event.payload[:sql]
      next unless Thread.current[:cc_configuration_request] && sql.start_with?('SELECT')
      next unless sql.include?('"accounts"') && sql.exclude?('FOR UPDATE')

      read << true
    end
  end

  def hold_account_change(change, defer_change: false)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Account.find(account.id).with_lock do
          change.call unless defer_change
          entered << true
          Timeout.timeout(15) { release.pop }
          change.call if defer_change
        end
      end
    rescue StandardError => e
      results << e
    end
  end

  def race_with_account_change(change, endpoint: nil, payload: nil, verb: :patch, defer_change: false)
    endpoint ||= "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy"
    payload ||= { limits: { voice: 60, whatsapp: 120 }, voice_required: false }
    observe_account_read
    hold_account_change(change, defer_change: defer_change)
    Timeout.timeout(8) { entered.pop }
    dispatch_configuration_request(verb, endpoint, payload)
    Timeout.timeout(8) { read.pop }
    wait_for_account_lock
    release << true
    Timeout.timeout(20) { workers.each(&:join) }
    results.pop
  end

  def wait_for_account_lock
    Timeout.timeout(8) do
      connection = ActiveRecord::Base.connection
      sql = "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = #{connection.quote(state.fetch(:request_pid))} AND wait_event_type = 'Lock')"
      connection.uncached { sleep 0.02 until connection.select_value(sql) }
    end
  end

  %w[eligibility profile].each do |source|
    it "does not change global ACW after #{source} is revoked during the account lock wait" do
      JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
      previous = JrcContactCenter::AcwPolicy.new(account: account).call
      change = lambda do
        member = account.account_users.find_by!(user: actor)
        if source == 'eligibility'
          JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
        else
          member.custom_role.update!(permissions: ['jrc_contact_center_view'])
        end
      end
      expect(race_with_account_change(change)).to eq(401)
      expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call).to eq(previous)
    end
  end

  it 'rejects an ACW snapshot superseded while the real HTTP request waits for Account FOR UPDATE' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    expected = JrcContactCenter::AcwPolicy.new(account: account.reload).revision
    change = lambda do
      JrcContactCenter::AcwPolicy.new(account: Account.find(account.id)).update!({ voice: 240, whatsapp: 300 })
    end
    payload = { limits: { voice: 60, whatsapp: 120 }, voice_required: false, expected_revision: expected }
    expect(race_with_account_change(change, payload: payload)).to eq(409)
    policy = JrcContactCenter::AcwPolicy.new(account: account.reload).call
    expect(policy.fetch(:limits)).to eq('voice' => 240, 'whatsapp' => 300)
    expect(policy.fetch(:voice_required)).to be(true)
    events = Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT)
    expect(events.count).to eq(1)
  end

  it 'rejects a stale write after the queue moves outside the authorized business unit' do
    status = race_with_queue_change(
      change: { unit_id: units.last.id }, verb: :patch,
      endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}",
      payload: { queue: { name: 'Forbidden stale edit' } }
    )
    expect(status).to eq(404)
    expect(queue.reload).to have_attributes(unit_id: units.last.id, name: 'Original')
  end

  it 'does not create membership after a concurrent deactivation of its parent queue' do
    status = race_with_queue_change(
      change: { status: 'inactive' }, verb: :post,
      endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships",
      payload: { queue_membership: { queue_id: queue.id, account_user_id: account.account_users.find_by!(user: actor).id,
                                     role: 'agent', active: true } }
    )
    expect(status).to eq(422)
    expect(queue.reload.status).to eq('inactive')
    expect(JrcContactCenter::QueueMembership.where(account: account)).to be_empty
    expect(Audited.audit_class.where(associated: account, auditable_type: 'JrcContactCenter::QueueMembership')).to be_empty
  end

  it 'rejects a same-scope stale revision after waiting for a concurrent configuration update' do
    expected = JrcContactCenter::ConfigurationRevision.token(queue)
    status = race_with_queue_change(
      change: { name: 'Concurrent committed state' }, verb: :patch,
      endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}",
      payload: { queue: { name: 'Stale draft' }, expected_revision: expected }
    )
    expect(status).to eq(409)
    expect(queue.reload.name).to eq('Concurrent committed state')
    trail = Audited.audit_class.where(auditable: queue, action: 'update', comment: JrcContactCenter::ConfigurationAudit::COMMENT)
    expect(trail.count).to eq(1)
  end

  it 'denies a queued write when eligibility was revoked after the initial authorization' do
    state[:before_release] = lambda do
      member = account.account_users.find_by!(user: actor)
      JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    end
    status = race_with_queue_change(
      change: {}, verb: :patch, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}",
      payload: { queue: { name: 'Forbidden after eligibility revocation' } }
    )
    expect(status).to eq(401)
    expect(queue.reload.name).to eq('Original')
    expect(Audited.audit_class.where(auditable: queue, action: 'update')).to be_empty
  end

  it 'denies a queued write when its functional profile was restricted during the lock wait' do
    state[:before_release] = lambda do
      account.account_users.find_by!(user: actor).custom_role.update!(permissions: ['jrc_contact_center_view'])
    end
    status = race_with_queue_change(
      change: {}, verb: :patch, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}",
      payload: { queue: { name: 'Forbidden after profile revocation' } }
    )
    expect(status).to eq(401)
    expect(queue.reload.name).to eq('Original')
    expect(Audited.audit_class.where(auditable: queue, action: 'update')).to be_empty
  end

  it 'rechecks recipient coverage after a real queue lock wait before reactivating membership' do
    recipient = create(:user, :contact_center_eligible, account: account)
    member = account.account_users.find_by!(user: recipient)
    coverage = JrcCrm::UserBusinessUnit.create!(
      account: account, user: recipient, scope: 'BUSINESS_UNIT', company: company, business_unit: business_units.first,
      active: true, structure_managed: true
    )
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, active: false)
    state[:before_release] = lambda do
      wait_for_account_lock
      coverage.update!(business_unit: business_units.last)
    end
    status = race_with_queue_change(
      change: {}, verb: :patch, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships/#{membership.id}",
      payload: { queue_membership: { active: true } }
    )
    expect(status).to eq(422)
    expect(membership.reload.active).to be(false)
    expect(Audited.audit_class.where(auditable: membership, action: 'update')).to be_empty
  end

  %w[eligibility profile feature].each do |source|
    it "does not change operator availability after #{source} is revoked during the account lock wait" do
      member = account.account_users.find_by!(user: actor)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_operate])
      previous = member.availability
      change = lambda do
        case source
        when 'eligibility' then JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
        when 'profile' then member.custom_role.update!(permissions: ['jrc_contact_center_view'])
        when 'feature' then Account.find(account.id).disable_features!('jrc_contact_center')
        end
      end
      status = race_with_account_change(
        change,
        endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state",
        payload: { agent_state: { state: 'available', command_id: "SYNTHETIC-#{source}", expected_state_version: '0' } }
      )
      expect(status).to eq(401)
      expect(member.reload.availability).to eq(previous)
      expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    end
  end

  def operating_write_payload(resource)
    owner = account.account_users.find_by!(user: actor)
    shared = { queue_id: queue.id, owner_account_user_id: owner.id }
    if resource == 'cases'
      { case: shared.merge(unit_id: units.first.id, channel: 'phone', category: 'general', summary: 'SYNTHETIC operating write') }
    else
      { callback: shared.merge(target_phone: '+5511999999999', scheduled_at: 1.hour.from_now.iso8601, idempotency_key: SecureRandom.uuid) }
    end
  end

  def revoke_operating_source(source, team: nil)
    member = account.account_users.find_by!(user: actor)
    case source
    when 'eligibility' then JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    when 'profile' then member.custom_role.update!(permissions: ['jrc_contact_center_view'])
    when 'feature' then Account.find(account.id).disable_features!('jrc_contact_center')
    when 'team' then TeamMember.find_by!(team: team, user: actor).destroy!
    when 'corporate'
      scope = JrcCrm::UserBusinessUnit.find_by!(account: account, user: actor, scope: 'BUSINESS_UNIT', structure_managed: true)
      scope.update!(business_unit: business_units.last)
    end
  end

  def fail_case_event_insert
    allow(JrcContactCenter::CaseEvent).to receive(:new).and_wrap_original do |original, *args, **kwargs, &block|
      event = original.call(*args, **kwargs, &block)
      allow(event).to receive(:save!).and_raise(ActiveRecord::StatementInvalid, 'SYNTHETIC mandatory case event unavailable')
      state[:mandatory_event] = event
      event
    end
  end

  context 'with native operating writes' do
    before do
      member = account.account_users.find_by!(user: actor)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_operate])
    end

    operating_sources = %w[eligibility profile feature team corporate].freeze
    %w[cases callbacks].each do |resource|
      operating_sources.each do |source|
        it "denies #{resource} creation after #{source} is revoked during the Account lock wait" do
          inherited_team = nil
          if source == 'team'
            member = account.account_users.find_by!(user: actor)
            member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
            inherited_team = create(:team, account: account)
            create(:team_member, team: inherited_team, user: actor)
            JrcContactCenter::AccessGrant.create!(account: account, team: inherited_team, allowed: ['jrc_contact_center_operate'])
          end
          context = { account: account, account_user: account.account_users.find_by!(user: actor), user: actor }
          expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?).to be(true)
          expect(JrcContactCenter::AccessScope.new(user_context: context).queues.exists?(queue.id)).to be(true)
          change = -> { revoke_operating_source(source, team: inherited_team) }
          endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/#{resource}"
          result = race_with_account_change(change, endpoint: endpoint, payload: operating_write_payload(resource), verb: :post)
          # A revoked Case unit is hidden by the native record scope, not an authorization grant.
          expected_status = resource == 'cases' && source == 'corporate' ? 404 : 401
          expect(result).to eq(expected_status)
          model = resource == 'cases' ? JrcContactCenter::Case : JrcContactCenter::Callback
          expect(model.where(account: account)).to be_empty
          expect(JrcContactCenter::CaseEvent.where(account: account)).to be_empty
        end
      end
    end

    it 'rolls back a created Case when its required native event cannot be inserted, without an outer fixture transaction' do
      fail_case_event_insert
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/cases"
      post endpoint, headers: headers, params: operating_write_payload('cases'), as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(state.fetch(:mandatory_event)).to have_received(:save!)
      expect(JrcContactCenter::Case.where(account: account)).to be_empty
      expect(JrcContactCenter::CaseEvent.where(account: account)).to be_empty
    end

    it 'rolls back a Case update with its required event while preserving committed history, without an outer fixture transaction' do
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/cases"
      post endpoint, headers: headers, params: operating_write_payload('cases'), as: :json
      expect(response).to have_http_status(:created)
      record = JrcContactCenter::Case.where(account: account).sole
      previous = record.attributes
      fail_case_event_insert
      patch "#{endpoint}/#{record.id}", headers: headers, params: { case: { status: 'waiting', summary: 'SYNTHETIC rejected' } }, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(state.fetch(:mandatory_event)).to have_received(:save!)
      expect(record.reload.attributes).to eq(previous)
      expect(record.events.pluck(:event_type)).to eq(['created'])
    end
  end

  context 'with mandatory local pause catalog auditing and fresh authority' do
    before do
      JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
      state[:catalog_endpoint] = "/api/v1/accounts/#{account.id}/jrc_contact_center/pause_catalog"
      state[:pause_entry] = { 'code' => 'synthetic_break', 'name' => 'SYNTHETIC committed pause', 'category' => 'SYNTHETIC',
                              'active' => true, 'default_minutes' => 30, 'unit_ids' => [], 'custom_role_ids' => [] }
      catalog = JrcContactCenter::PauseCatalog.new(account: account)
      state[:catalog_payload] = { pause_catalog: { enforced: false, entries: [state.fetch(:pause_entry)] }, expected_revision: catalog.revision }
    end

    %w[eligibility profile corporate].each do |source|
      it "denies catalog mutation after #{source} is withdrawn while waiting for the native Account lock" do
        previous = account.reload.settings.deep_dup
        change = lambda do
          case source
          when 'eligibility'
            member = account.account_users.find_by!(user: actor)
            JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
          when 'profile' then account.account_users.find_by!(user: actor).custom_role.update!(permissions: ['jrc_contact_center_view'])
          when 'corporate' then JrcCrm::UserBusinessUnit.find_by!(account: account, user: actor, scope: 'GROUP').destroy!
          end
        end
        status = race_with_account_change(change, endpoint: state.fetch(:catalog_endpoint), payload: state.fetch(:catalog_payload))
        expect(status).to eq(401)
        expect(account.reload.settings).to eq(previous)
        expect(Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT)).to be_empty
      end
    end

    it 'rolls back the persisted catalog if inserting the mandatory audit fails, without an outer fixture transaction' do
      previous = account.reload.settings.deep_dup
      allow(Audited.audit_class).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        values = kwargs.presence || args.first
        if values[:comment] == JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT
          state[:mandatory_pause_audit_reached] = true
          raise ActiveRecord::StatementInvalid, 'SYNTHETIC pause audit insertion unavailable'
        end
        original.call(*args, **kwargs)
      end
      patch state.fetch(:catalog_endpoint), headers: headers, params: state.fetch(:catalog_payload), as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(state[:mandatory_pause_audit_reached]).to be(true)
      expect(Account.find(account.id).settings).to eq(previous)
      expect(Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT)).to be_empty
    end

    it 'checks newly activated enforcement after a waiting operator request acquires the Account lock' do
      member = account.account_users.find_by!(user: actor)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_operate])
      change = lambda do
        fresh = JrcContactCenter::PauseCatalog.new(account: Account.find(account.id))
        fresh.update!({ 'enforced' => true, 'entries' => [state.fetch(:pause_entry)] }, expected_revision: fresh.revision, activation_confirmed: true)
      end
      payload = { agent_state: { state: 'paused', reason_code: 'legacy_free', expected_state_version: '0', command_id: SecureRandom.uuid } }
      status = race_with_account_change(change, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", payload: payload)
      expect(status).to eq(422)
      expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
      fresh = JrcContactCenter::PauseCatalog.new(account: Account.find(account.id))
      expect(fresh.call.fetch('enforced')).to be(true)
    end
  end

  context 'with a newly required private pause justification' do
    before { JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true) }

    it 'checks the committed requirement after a waiting operator acquires the native Account lock' do
      member = account.account_users.find_by!(user: actor)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_operate])
      entry = { 'code' => 'synthetic_private', 'name' => 'SYNTHETIC private pause', 'category' => 'SYNTHETIC',
                'active' => true, 'default_minutes' => 30, 'unit_ids' => [], 'custom_role_ids' => [] }
      catalog = JrcContactCenter::PauseCatalog.new(account: account)
      catalog.update!({ 'enforced' => true, 'entries' => [entry] }, expected_revision: catalog.revision, activation_confirmed: true)
      previous = member.reload.availability
      change = lambda do
        fresh = JrcContactCenter::PauseCatalog.new(account: Account.find(account.id))
        fresh.update!({ 'enforced' => true, 'entries' => [entry.merge('justification_required' => true)] }, expected_revision: fresh.revision)
      end
      payload = { agent_state: { state: 'paused', reason_code: entry.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0' } }
      status = race_with_account_change(change, endpoint: "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", payload: payload)
      expect(status).to eq(422)
      expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
      expect(member.reload.availability).to eq(previous)
    end
  end

  context 'with confirmed last eligible queue withdrawal' do
    before do
      person = create(:user, :contact_center_eligible, account: account, role: :agent)
      member = account.account_users.find_by!(user: person)
      JrcCrm::UserBusinessUnit.create!(account: account, user: person, scope: 'BUSINESS_UNIT', company: company,
                                       business_unit: business_units.first, active: true, structure_managed: true)
      state[:withdrawal_member] = member
      state[:withdrawal_membership] = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    end

    it 'detects loss of the other eligible agent while the requested withdrawal waits for the Account lock' do
      person = create(:user, :contact_center_eligible, account: account, role: :agent)
      peer = account.account_users.find_by!(user: person)
      JrcCrm::UserBusinessUnit.create!(account: account, user: person, scope: 'BUSINESS_UNIT', company: company,
                                       business_unit: business_units.first, active: true, structure_managed: true)
      JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: peer)
      membership = state.fetch(:withdrawal_membership)
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships/#{membership.id}"
      payload = { queue_membership: { active: false }, expected_revision: JrcContactCenter::ConfigurationRevision.token(membership) }
      change = -> { JrcContactCenter::AccessGrant.find_by!(account: account, account_user: peer).update!(eligible: false) }
      expect(race_with_account_change(change, endpoint: endpoint, payload: payload)).to eq(409)
      expect(membership.reload.active).to be(true)
      expect(Audited.audit_class.where(auditable: membership, action: 'update')).to be_empty
    end

    it 'rolls back a confirmed withdrawal when its mandatory native audit insert fails' do
      membership = state.fetch(:withdrawal_membership)
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships/#{membership.id}"
      payload = { queue_membership: { active: false }, expected_revision: JrcContactCenter::ConfigurationRevision.token(membership) }
      patch endpoint, headers: headers, params: payload, as: :json
      expect(response).to have_http_status(:conflict)
      receipt = response.parsed_body.fetch('review').fetch('review_token')
      allow(Audited.audit_class).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
        values = kwargs.presence || args.first
        if values[:auditable] == membership && values[:action] == 'update'
          state[:mandatory_withdrawal_audit] = true
          raise ActiveRecord::StatementInvalid, 'SYNTHETIC withdrawal audit insertion unavailable'
        end
        original.call(*args, **kwargs)
      end
      confirmed = payload.merge(manager_confirmation: { confirmed: true, review_token: receipt })
      patch endpoint, headers: headers, params: confirmed, as: :json
      expect(response).to have_http_status(:internal_server_error)
      expect(state[:mandatory_withdrawal_audit]).to be(true)
      expect(JrcContactCenter::QueueMembership.find(membership.id).active).to be(true)
      expect(Audited.audit_class.where(auditable: membership, action: 'update')).to be_empty
    end
  end

  %w[eligibility profile coverage].each do |source|
    it "does not complete native ACW after #{source} is revoked while waiting for the account lock" do
      member = account.account_users.find_by!(user: actor)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
      call = JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                                   direction: 'inbound', status: 'connected', started_at: 2.minutes.ago,
                                                   answered_at: 1.minute.ago, current_unit_id: units.first.id, current_queue_id: queue.id)
      JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, queue: queue,
                                        direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
      call.update!(status: 'ended', ended_at: Time.current)
      record = JrcContactCenter::Qualification.find_by!(account: account, call_session: call, account_user: member)
      change = lambda do
        case source
        when 'eligibility' then JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
        when 'profile' then member.custom_role.update!(permissions: ['jrc_contact_center_view'])
        else JrcCrm::UserBusinessUnit.find_by!(account: account, user: actor).update!(business_unit: business_units.last)
        end
      end
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}"
      payload = { qualification: { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC blocked write' } }
      status = race_with_account_change(change, endpoint: endpoint, payload: payload)
      expect(status).to eq(source == 'coverage' ? 404 : 401)
      expect(record.reload).to have_attributes(completed_at: nil, reason_code: nil, notes: nil)
      expect(JrcContactCenter::AgentStateEvent.find_by!(account: account, external_event_id: "qualification:#{record.id}:pending").ended_at).to be_nil
    end
  end

  routing_sources = %w[eligibility profile coverage]
  %w[create update].each do |operation|
    routing_sources.each do |source|
      it "does not #{operation} native routing rules after #{source} changes during the account lock wait" do
        member = account.account_users.find_by!(user: actor)
        rule = if operation == 'update'
                 JrcContactCenter::RoutingRule.create!(account: account, created_by_account_user: member, version: 1,
                                                       rule_key: 'synthetic-existing', kind: 'ddd', source_value: '11',
                                                       target_unit: units.first, target_queue: queue, priority: 1, state: 'draft')
               end
        rows = JrcContactCenter::RoutingRule.where(account: account).order(:id)
        before = rows.pluck(:id, :source_value, :priority, :state)
        change = lambda do
          case source
          when 'eligibility' then JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
          when 'profile' then member.custom_role.update!(permissions: ['jrc_contact_center_view'])
          else JrcCrm::UserBusinessUnit.find_by!(account: account, user: actor).update!(business_unit: business_units.last)
          end
        end
        endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/routing_rules"
        endpoint += "/#{rule.id}" if rule
        payload = { routing_rule: { version: 1, rule_key: 'synthetic-new', kind: 'ddd', source_value: '21',
                                    target_unit_id: units.first.id, target_queue_id: queue.id, priority: 2, state: 'draft' } }
        status = race_with_account_change(change, endpoint: endpoint, payload: payload, verb: operation == 'create' ? :post : :patch)
        expect(status).to eq(source == 'coverage' ? 404 : 401)
        observed = ActiveRecord::Base.uncached { rows.pluck(:id, :source_value, :priority, :state) }
        expect(observed).to eq(before)
      end
    end
  end

  it 'rolls back routing and its native audit together in the actual nontransactional owned HTTP boundary' do
    headers
    allow(Audited.audit_class).to receive(:create!).and_wrap_original do |original, *args, **kwargs|
      values = kwargs.presence || args.first
      if values[:auditable].is_a?(JrcContactCenter::RoutingRule)
        state[:routing_audit_attempt] = true
        state[:routing_persisted_before_audit] = JrcContactCenter::RoutingRule.exists?(account: account, id: values[:auditable].id)
        raise ActiveRecord::RecordInvalid, Audited.audit_class.new
      end
      original.call(*args, **kwargs)
    end
    payload = { routing_rule: { version: 1, rule_key: 'synthetic-audit-rollback', kind: 'ddd', source_value: '11',
                                target_unit_id: units.first.id, target_queue_id: queue.id, priority: 1, state: 'draft' } }
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/routing_rules", headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(state[:routing_audit_attempt]).to be(true)
    expect(state[:routing_persisted_before_audit]).to be(true)
    expect(JrcContactCenter::RoutingRule.where(account: account)).to be_empty
    expect(Audited.audit_class.where(associated: account, auditable_type: 'JrcContactCenter::RoutingRule')).to be_empty
  end

  it 'does not activate a required ending queue after eligibility is revoked while the request waits for the native account lock' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    entry = { code: 'synthetic', name: 'SYNTHETIC reason', category: 'SYNTHETIC', description: '', order: 0, active: true }
    payload = { limits: { voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], voice_reason_required_queue_ids: [queue.id.to_s],
                voice_reason_confirmation: true, expected_revision: JrcContactCenter::AcwPolicy.new(account: account.reload).revision }
    change = -> { JrcContactCenter::AccessGrant.find_by!(account_user: account.account_users.find_by!(user: actor)).update!(eligible: false) }
    expect(race_with_account_change(change, payload: payload)).to eq(401)
    expect(JrcContactCenter::EndingReasonVersion.where(account: account)).to be_empty
    expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
  end

  it 'does not overwrite a newer catalogue and exact immutable version when an earlier HTTP reviewer waits for the same account lock' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    entry = { code: 'synthetic', name: 'SYNTHETIC newest', category: 'SYNTHETIC', description: '', order: 0, active: true }
    expected = JrcContactCenter::AcwPolicy.new(account: account.reload).revision
    payload = { limits: { voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry.merge(name: 'SYNTHETIC stale')],
                voice_reason_required_queue_ids: [queue.id.to_s], voice_reason_confirmation: true, expected_revision: expected }
    change = lambda do
      fresh = JrcContactCenter::AcwPolicy.new(account: Account.find(account.id))
      fresh.update!(
        { voice: 180, whatsapp: 180 },
        voice_reason_catalog: [entry], voice_reason_required_queue_ids: [queue.id.to_s],
        voice_reason_confirmation: true, expected_revision: fresh.revision
      )
    end
    expect(race_with_account_change(change, payload: payload)).to eq(409)
    version = JrcContactCenter::EndingReasonVersion.where(account: account).sole
    expect(version.definition.fetch('entries').sole.fetch('name')).to eq('SYNTHETIC newest')
    expect(version.revision).to eq(1)
    expect(JrcContactCenter::AcwEndingReasons.new(account: account.reload).call).to eq(version.definition)
  end

  %w[create update].each do |operation|
    it "does not #{operation} a queue after the authenticated actor becomes unconfirmed during the Account lock wait" do
      previous = JrcContactCenter::Queue.where(account: account).order(:id).pluck(:id, :name, :code, :unit_id)
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/queues"
      endpoint += "/#{queue.id}" if operation == 'update'
      payload = { queue: { unit_id: units.first.id, code: 'SYNTHETIC-UNCONFIRMED', name: 'Forbidden after deactivation' } }
      change = -> { User.find(actor.id).update!(confirmed_at: nil) }
      status = race_with_account_change(
        change, endpoint: endpoint, payload: payload, verb: operation == 'create' ? :post : :patch, defer_change: true
      )
      expect(status).to eq(401)
      expect(JrcContactCenter::Queue.where(account: account).order(:id).pluck(:id, :name, :code, :unit_id)).to eq(previous)
      expect(actor.reload.active_for_authentication?).to be(false)
    end
  end

  it 'does not enroll a newly unconfirmed recipient after a committed account lock wait despite its retained grant' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    recipient = create(:user, :contact_center_eligible, account: account)
    member = account.account_users.find_by!(user: recipient)
    JrcCrm::UserBusinessUnit.create!(account: account, user: recipient, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
                                     company: company, active: true, structure_managed: true)
    change = -> { User.find(recipient.id).update!(confirmed_at: nil) }
    payload = { queue_membership: { queue_id: queue.id, account_user_id: member.id } }
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships"
    status = race_with_account_change(change, endpoint: endpoint, payload: payload, verb: :post, defer_change: true)
    expect(status).to eq(422)
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
    expect(JrcContactCenter::AccessGrant.find_by!(account_user: member).eligible).to be(true)
    expect(recipient.reload.active_for_authentication?).to be(false)
  end

  %w[profile coverage authentication].each do |origin|
    it "does not create an institutional folder after #{origin} is revoked while waiting for the native account lock" do
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_folders"
      payload = { folder: { unit_id: units.first.id, name: 'SYNTHETIC forbidden folder' } }
      change = lambda do
        case origin
        when 'profile'
          account.account_users.find_by!(user: actor).custom_role.update!(permissions: ['jrc_contact_center_view'])
        when 'coverage'
          JrcCrm::UserBusinessUnit.where(account: account, user: actor).find_each { |coverage| coverage.update!(active: false) }
        else
          User.find(actor.id).update!(confirmed_at: nil)
        end
      end
      status = race_with_account_change(change, endpoint: endpoint, payload: payload, verb: :post, defer_change: true)
      expect(status).to eq(origin == 'coverage' ? 404 : 401)
      expect(JrcContactCenter::AudioFolder.where(account: account)).to be_empty
      expect(Audited.audit_class.where(associated: account, auditable_type: 'JrcContactCenter::AudioFolder')).to be_empty
    end
  end

  it 'rejects a stale institutional folder revision after the actual request waits for a committed edit' do
    folder = JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, name: 'SYNTHETIC original folder')
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_folders/#{folder.id}"
    payload = { folder: { name: 'SYNTHETIC stale folder' }, expected_revision: JrcContactCenter::ConfigurationRevision.token(folder) }
    change = -> { JrcContactCenter::AudioFolder.find(folder.id).update!(name: 'SYNTHETIC newer folder') }
    expect(race_with_account_change(change, endpoint: endpoint, payload: payload, defer_change: true)).to eq(409)
    expect(folder.reload.name).to eq('SYNTHETIC newer folder')
  end

  it 'rechecks parent ancestry after the native lock wait instead of committing a concurrent hierarchy cycle' do
    first = JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, name: 'SYNTHETIC first folder')
    second = JrcContactCenter::AudioFolder.create!(account: account, unit: units.first, name: 'SYNTHETIC second folder')
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_folders/#{first.id}"
    payload = { folder: { parent_id: second.id }, expected_revision: JrcContactCenter::ConfigurationRevision.token(first) }
    change = -> { JrcContactCenter::AudioFolder.find(second.id).update!(parent_id: first.id) }
    expect(race_with_account_change(change, endpoint: endpoint, payload: payload, defer_change: true)).to eq(422)
    expect(first.reload.parent_id).to be_nil
    expect(second.reload.parent_id).to eq(first.id)
  end

  %w[users teams].each do |kind|
    it "does not write #{kind} grants after actor authentication is withdrawn during the committed account lock wait" do
      JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
      actor_member = account.account_users.find_by!(user: actor)
      actor_member.custom_role.update!(permissions: JrcContactCenter::ModulePolicy::PERMISSIONS)
      subject = kind == 'teams' ? create(:team, account: account) : create(:user, account: account).account_users.find_by!(account: account)
      service = JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: actor_member, user: actor })
      grant = service.grant_for(subject)
      attributes = { allowed: ['jrc_contact_center_view'] }
      attributes[:eligible] = true if kind == 'users'
      payload = { authorization: attributes, expected_revision: service.revision(subject, grant) }
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations/#{kind}/#{subject.id}"
      before = JrcContactCenter::AccessGrant.where(account: account).order(:id).map(&:attributes)
      change = -> { User.find(actor.id).update!(confirmed_at: nil) }
      expect(race_with_account_change(change, endpoint: endpoint, payload: payload, defer_change: true)).to eq(401)
      expect(JrcContactCenter::AccessGrant.where(account: account).order(:id).map(&:attributes)).to eq(before)
      expect(actor.reload.active_for_authentication?).to be(false)
    end
  end
end
