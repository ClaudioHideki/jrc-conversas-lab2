require 'rails_helper'
require 'timeout'

RSpec.describe 'Explicit ending reason confirmation with real competing requests', type: :request do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic confirmation concurrency database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with a frozen ending reason catalogue'

  def perform_confirmation(endpoint, token, values)
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.post(endpoint, headers: token, params: values, as: :json)
    { status: client.response.status, body: client.response.parsed_body }
  end

  def confirmation_contender(state, endpoint, token, values)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        state[:ready] << ActiveRecord::Base.connection.raw_connection.backend_pid
        Timeout.timeout(15) { state[:gate].pop }
        state[:results] << perform_confirmation(endpoint, token, values)
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_confirmation_contenders(state, count)
    ids = Timeout.timeout(8) { Array.new(count) { state[:ready].pop } }
    raise 'Distinct PostgreSQL connections required' unless ids.uniq.length == count

    count.times { state[:gate] << true }
    quoted = ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(',')
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{quoted}) AND wait_event_type = 'Lock'"
    Timeout.timeout(8) do
      ActiveRecord::Base.connection.uncached { sleep 0.02 until ActiveRecord::Base.connection.select_value(sql).to_i == count }
    end
  end

  def competing_confirmations(values)
    token = actor.create_new_auth_token
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}/confirm_reason"
    state = { ready: Queue.new, gate: Queue.new, results: Queue.new, workers: [] }
    account.with_lock do
      values.each { |value| state[:workers] << confirmation_contender(state, endpoint, token, value) }
      wait_for_confirmation_contenders(state, values.length)
      yield if block_given?
    end
    collect_confirmation_results(state, values.length)
  ensure
    join_confirmation_contenders(state) if state
  end

  def collect_confirmation_results(state, count)
    rows = Timeout.timeout(20) do
      state[:workers].each(&:join)
      Array.new(count) { state[:results].pop }
    end
    raise rows.grep(Exception).first if rows.any?(Exception)

    rows
  end

  def join_confirmation_contenders(state)
    state[:workers].length.times { state[:gate] << true }
    state[:workers].each { |worker| worker.join(20) }
    raise 'Synthetic confirmation still active' if state[:workers].any?(&:alive?)
  end

  it 'accepts one classification under different request keys, returning a conflict to the other actual HTTP request' do
    revision = JrcContactCenter::QualificationDraftRevision.token(record)
    values = Array.new(2) do
      { qualification: { reason_code: entry.fetch('code') }, expected_draft_revision: revision, idempotency_key: SecureRandom.uuid }
    end
    rows = competing_confirmations(values)
    expect(rows.pluck(:status).sort).to eq([200, 409])
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account, source_qualification_id: record.id).count).to eq(1)
    expect(record.reload.completed_at).to be_nil
  end

  it 'replays concurrent identical requests without creating duplicate classification evidence or closing ACW' do
    values = { qualification: { reason_code: entry.fetch('code') },
               expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record),
               idempotency_key: SecureRandom.uuid }
    rows = competing_confirmations([values, values])
    expect(rows.pluck(:status)).to eq([200, 200])
    expect(rows.map { |row| row.fetch(:body).dig('item', 'ending_reason_confirmation', 'id') }.uniq.length).to eq(1)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account).count).to eq(1)
    expect(record.reload.completed_at).to be_nil
  end

  it 'denies an already queued confirmation when current operating eligibility is revoked before the account lock is released' do
    values = { qualification: { reason_code: entry.fetch('code') },
               expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record),
               idempotency_key: SecureRandom.uuid }
    rows = competing_confirmations([values]) { JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false) }
    expect(rows.first.fetch(:status)).to eq(401)
    expect(JrcContactCenter::EndingReasonConfirmation.where(account: account)).to be_empty
    expect(record.reload.reason_code).to be_nil
  end
end
