require 'rails_helper'
require 'timeout'

RSpec.describe 'Native team supervision competing reviewed writes', type: :request do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:role) { create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS) }
  let(:team) { create(:team, account: account) }
  let(:workers) { [] }
  let(:ready) { Queue.new }
  let(:release) { Queue.new }
  let(:results) { Queue.new }
  let(:state) { {} }

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && config.database == 'corporate_gratuity_disposable' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
    raise 'Owned synthetic committed database required' unless owned && !ActiveRecord::Base.connection.transaction_open?

    state[:owned] = true
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(custom_role: role)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
  end

  after do
    next unless state[:owned]

    workers.length.times { release << true }
    workers.each { |worker| worker.join(20) }
    raise 'Synthetic team supervision worker still active' if workers.any?(&:alive?)

    if account.persisted?
      account.jrc_crm_user_business_units.destroy_all
      account.jrc_crm_team_scopes.destroy_all
      account.teams.destroy_all
      account.destroy!
    end
  end

  def dispatch_supervision(endpoint, headers, payload, barrier: false)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        ready << ActiveRecord::Base.connection.raw_connection.backend_pid
        Timeout.timeout(10) { release.pop } if barrier
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.patch(endpoint, headers: headers, params: payload, as: :json)
        results << session.response.status
      end
    rescue StandardError => e
      results << e
    end
  end

  it 'accepts exactly one real concurrent request and refuses the stale revision without duplicate metadata or audit' do
    user = create(:user, :contact_center_eligible, account: account, role: :agent)
    selected = account.account_users.find_by!(user: user)
    selected.update!(custom_role: role)
    account.jrc_crm_user_business_units.create!(user: user, scope: 'GROUP', structure_managed: true)
    headers = actor.create_new_auth_token
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/team_supervisions/#{team.id}"
    get endpoint, headers: headers
    revision = response.parsed_body.fetch('item').fetch('revision')
    payload = { supervision: { primary_account_user_id: selected.id.to_s, additional_account_user_ids: [] }, expected_revision: revision }
    2.times { dispatch_supervision(endpoint, headers, payload, barrier: true) }
    Timeout.timeout(10) { 2.times { ready.pop } }
    2.times { release << true }
    Timeout.timeout(25) { workers.each(&:join) }
    outcomes = Array.new(2) { results.pop }
    expect(outcomes).to all(be_a(Integer))
    expect(outcomes.sort).to eq([200, 409])
    row = JrcContactCenter::TeamSupervision.where(team: team).sole
    expect(row.account_user_id).to eq(selected.id)
    expect(Audited.audit_class.where(auditable_type: row.class.name, auditable_id: row.id, action: 'create').count).to eq(1)
    expect(TeamMember.where(team: team)).to be_empty
    expect(JrcContactCenter::QueueMembership.where(account: account, account_user: selected)).to be_empty
  end

  %w[recipient actor].each do |target|
    it "reauthorizes #{target} after a real Account lock wait and rejects a previously reviewed selection after revocation" do
      user = create(:user, :contact_center_eligible, account: account, role: :agent)
      selected = account.account_users.find_by!(user: user)
      selected.update!(custom_role: role)
      account.jrc_crm_user_business_units.create!(user: user, scope: 'GROUP', structure_managed: true)
      headers = actor.create_new_auth_token
      endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/team_supervisions/#{team.id}"
      get endpoint, headers: headers
      payload = { supervision: { primary_account_user_id: selected.id.to_s, additional_account_user_ids: [] },
                  expected_revision: response.parsed_body.fetch('item').fetch('revision') }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Account.find(account.id).with_lock do
            ready << true
            Timeout.timeout(15) { release.pop }
            if target == 'recipient'
              JrcContactCenter::AccessGrant.find_by!(account_user: selected).update!(eligible: false)
            else
              CustomRole.find(role.id).update!(permissions: ['jrc_contact_center_view'])
            end
          end
        end
      rescue StandardError => e
        results << e
      end
      Timeout.timeout(10) { ready.pop }
      dispatch_supervision(endpoint, headers, payload)
      pid = Timeout.timeout(10) { ready.pop }
      Timeout.timeout(8) do
        loop do
          sql = "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = #{Integer(pid)} AND wait_event_type = 'Lock' " \
                "AND query LIKE '%accounts%' AND query LIKE '%FOR UPDATE%')"
          break if ActiveRecord::Base.connection.uncached { ActiveRecord::Base.connection.select_value(sql) }

          sleep 0.02
        end
      end
      release << true
      Timeout.timeout(25) { workers.each(&:join) }
      expect(results.size).to eq(1)
      expect(results.pop).to eq(target == 'recipient' ? 422 : 401)
      expect(JrcContactCenter::TeamSupervision.where(account: account)).to be_empty
      expect(TeamMember.where(team: team)).to be_empty
    end
  end
end
