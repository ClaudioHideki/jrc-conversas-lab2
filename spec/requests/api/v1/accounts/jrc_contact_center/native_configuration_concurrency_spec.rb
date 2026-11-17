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
      JrcContactCenter::QueueMembership.where(account: account).destroy_all
      JrcContactCenter::Queue.where(account: account).destroy_all
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

  def hold_account_change(change)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Account.find(account.id).with_lock do
          change.call
          entered << true
          Timeout.timeout(15) { release.pop }
        end
      end
    rescue StandardError => e
      results << e
    end
  end

  def race_with_account_change(change)
    observe_account_read
    hold_account_change(change)
    Timeout.timeout(8) { entered.pop }
    dispatch_configuration_request(:patch, "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy",
                                   { limits: { voice: 60, whatsapp: 120 }, voice_required: false })
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
end
