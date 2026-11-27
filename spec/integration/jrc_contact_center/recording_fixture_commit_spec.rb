# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_pause_seed')

# Real committed lifecycle + authenticated native read. A transactional factory
# cannot reproduce the after-commit qualification that caused the bootstrap failure.
RSpec.describe 'Owned committed recording fixture and native read', type: :request, pabx: true do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    conditions = [Rails.env.test?, ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted',
                  ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116',
                  config.configuration_hash[:host] == '127.0.0.1', ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15',
                  ApplicationRecord.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test']
    raise 'Owned committed recording fixture database required' unless conditions.all?
    raise 'An outer fixture transaction would hide the native lifecycle' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  let(:project_key) { "committed-recording-#{SecureRandom.hex(10)}" }
  let(:fixture_name) { "SYNTHETIC pause #{project_key}-recordings" }
  let(:payload) do
    raise 'Preserve a pre-existing fixture' if Account.exists?(name: fixture_name)

    @owned_creation_started = true
    JrcContactCenter::SyntheticPauseSeed.call(projects: [project_key], scenarios: ['recordings']).fetch(project_key).fetch('recordings')
  end

  after do
    next unless @owned_creation_started

    account = Account.find_by(name: fixture_name)
    next unless account

    users = account.account_users.pluck(:user_id)
    Account.where(id: account.id, name: fixture_name).delete_all
    User.where(id: users).where.missing(:account_users).delete_all
  end

  it 'reuses the actual committed qualification and preserves its full state and native counts through a real API read' do
    source = payload.fetch(:ending_context)
    account = Account.find(payload.fetch(:account_id))
    row = JrcContactCenter::Qualification.where(account: account).find(source.fetch(:qualification_id))
    original = row.attributes
    counts = [JrcContactCenter::Qualification.where(account: account).count,
              JrcContactCenter::EndingActionOrigin.where(account: account).count, JrcContactCenter::Command.where(account: account).count]
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{source.fetch(:recording_id)}/ending_context",
        headers: payload.fetch(:operator), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([{ 'id' => row.id.to_s, 'account_user_id' => row.account_user_id.to_s,
                                                         'started_at' => row.started_at&.iso8601, 'completed_at' => row.completed_at&.iso8601 }])
    expect(counts.first).to be_positive
    expect(counts.drop(1)).to eq([0, 0])
    expect(row.reload.attributes).to eq(original)
    after_counts = [JrcContactCenter::Qualification.where(account: account).count,
                    JrcContactCenter::EndingActionOrigin.where(account: account).count, JrcContactCenter::Command.where(account: account).count]
    expect(after_counts).to eq(counts)
  end

  it 'fails loudly instead of creating ACW when the requested native actor has no qualification for that source' do
    source = payload.fetch(:ending_context)
    account = Account.find(payload.fetch(:account_id))
    record = TelephonyCallRecord.where(account: account).find(source.fetch(:recording_id))
    participants = JrcContactCenter::Qualification.where(account: account, call_session_id: source.fetch(:call_session_id)).select(:account_user_id)
    absent = account.account_users.where.not(id: participants).order(:id).first!
    fixture = JrcContactCenter::SyntheticRecordingsSeed.new(account, absent, absent, [])
    count = JrcContactCenter::Qualification.where(account: account).count
    expect { fixture.send(:owned_ending_context, record) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::Qualification.where(account: account).count).to eq(count)
  end

  it 'rejects an unknown scenario before creating or changing any account' do
    count = Account.count
    expect do
      JrcContactCenter::SyntheticPauseSeed.call(projects: [project_key], scenarios: ['unknown'])
    end.to raise_error(RuntimeError, 'Unknown synthetic scenarios')
    expect(Account.count).to eq(count)
  end
end
