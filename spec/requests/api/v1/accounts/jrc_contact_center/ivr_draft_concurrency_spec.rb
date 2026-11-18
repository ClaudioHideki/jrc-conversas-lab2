require 'rails_helper'
require 'timeout'

RSpec.describe 'Local IVR real HTTP concurrency', type: :request do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC concurrency unit', kind: 'sac') }
  let(:definition) { { 'schema_version' => 1, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] } }
  let(:values) { { name: 'SYNTHETIC initial', status: 'draft', definition: definition, expected_revision: 0, request_id: SecureRandom.uuid } }
  let(:draft) do
    context = { account: account, account_user: member, user: actor }
    JrcContactCenter::IvrDraftWrite.new(context: context).call(input: JrcContactCenter::IvrDraftInput.new(**values), unit_id: unit.id).fetch(:draft)
  end
  let(:workers) { [] }
  let(:ready) { Queue.new }
  let(:gate) { Queue.new }
  let(:results) { Queue.new }
  let(:state) { {} }

  before do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic concurrency database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?

    state[:ready] = true
    account.enable_features!('jrc_contact_center')
    headers
    draft
  end

  after do
    if state[:ready]
      workers.length.times { gate << true }
      workers.each { |worker| worker.join(20) }
      raise 'Synthetic IVR request still active' if workers.any?(&:alive?)

      Account.transaction do
        JrcContactCenter::Unit.where(account: account).destroy_all
        account.destroy!
      end
    end
  end

  # Both requests execute the real router, token authentication, controller and PostgreSQL transaction.
  def dispatch_ivr(payload)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/ivr_drafts/#{draft.id}"
    workers << Thread.new { perform_ivr_request(endpoint, payload) }
  end

  def perform_ivr_request(endpoint, payload)
    ActiveRecord::Base.connection_pool.with_connection do
      ready << ActiveRecord::Base.connection.raw_connection.backend_pid
      Timeout.timeout(15) { gate.pop }
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.patch(endpoint, headers: headers, params: { ivr_draft: payload }, as: :json)
      results << { status: session.response.status, body: session.response.parsed_body }
    end
  rescue StandardError => e
    results << e
  end

  def wait_for_real_locks(count)
    ids = Timeout.timeout(8) { Array.new(count) { ready.pop } }
    count.times { gate << true }
    connection = ActiveRecord::Base.connection
    quoted = ids.map { |id| connection.quote(id) }.join(',')
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{quoted}) AND wait_event_type = 'Lock'"
    Timeout.timeout(8) { connection.uncached { sleep 0.02 until connection.select_value(sql).to_i == count } }
  end

  def collected_results(count)
    rows = Timeout.timeout(20) do
      workers.each(&:join)
      Array.new(count) { results.pop }
    end
    errors = rows.grep(Exception)
    raise errors.first if errors.any?

    rows
  end

  it 'accepts exactly one writer when two different operations expect the same prior revision' do
    account.with_lock do
      %w[A B].each do |suffix|
        dispatch_ivr(values.merge(name: "SYNTHETIC contender #{suffix}", expected_revision: 1, request_id: SecureRandom.uuid))
      end
      wait_for_real_locks(2)
    end
    rows = collected_results(2)
    expect(rows.pluck(:status).sort).to eq([200, 409])
    expect(draft.latest_version.revision).to eq(2)
    expect(draft.versions.count).to eq(2)
    expect(draft.versions.order(:revision).pluck(:revision)).to eq([1, 2])
  end

  it 'returns one durable operation receipt to simultaneous retries with the same UUID' do
    payload = values.merge(name: 'SYNTHETIC same operation', expected_revision: 1, request_id: SecureRandom.uuid)
    account.with_lock do
      2.times { dispatch_ivr(payload) }
      wait_for_real_locks(2)
    end
    rows = collected_results(2)
    expect(rows.pluck(:status)).to eq([200, 200])
    expect(rows.map { |row| row.fetch(:body).fetch('replayed') }).to contain_exactly(false, true)
    expect(rows.map { |row| row.fetch(:body).fetch('item').fetch('revision') }).to eq([2, 2])
    expect(draft.versions.count).to eq(2)
  end

  it 'rejects a write whose eligibility was revoked while its real request waited for the account lock' do
    account.with_lock do
      JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
      dispatch_ivr(values.merge(name: 'SYNTHETIC forbidden', expected_revision: 1, request_id: SecureRandom.uuid))
      wait_for_real_locks(1)
    end
    result = collected_results(1).first
    expect(result.fetch(:status)).to eq(401)
    expect(draft.latest_version.name).to eq('SYNTHETIC initial')
    expect(draft.versions.count).to eq(1)
  end
end
