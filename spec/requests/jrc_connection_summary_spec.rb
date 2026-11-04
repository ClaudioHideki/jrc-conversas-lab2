require 'rails_helper'

RSpec.describe 'Broker connection summary', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_broker/inboxes/#{inbox.id}/summary" }

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('jrc_broker')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'reads an offline connection without contacting the Broker or inventing unavailable averages and agent counts' do
    expect(JrcBroker::Client).not_to receive(:new)
    get url, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('inbox_id' => inbox.id, 'name' => inbox.name, 'policy' => nil, 'teams' => [])
    expect(response.parsed_body['metrics']).to include('conversations_count' => 0, 'avg_first_response_time' => nil,
                                                     'avg_resolution_time' => nil, 'eligible_agents' => nil,
                                                     'first_response_sample_count' => 0, 'resolution_sample_count' => 0,
                                                     'unit' => 'seconds')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'counts only this inbox and account in the thirty-day window and averages genuine reporting samples' do
    travel_to Time.utc(2026, 11, 4, 12) do
      create(:conversation, account: account, inbox: inbox, created_at: 30.days.ago)
      create(:conversation, account: account, inbox: inbox, created_at: 1.day.ago)
      create(:conversation, account: account, inbox: inbox, created_at: 30.days.ago - 1.second)
      create(:conversation, account: account, inbox: inbox, created_at: 1.day.from_now)
      other_inbox = create(:channel_api, account: account).inbox
      create(:conversation, account: account, inbox: other_inbox, created_at: 1.day.ago)
      foreign = create(:account)
      foreign_inbox = create(:channel_api, account: foreign).inbox
      [0, 120].each do |value|
        ReportingEvent.create!(account: account, inbox: inbox, name: 'first_response', value: value, created_at: 1.day.ago)
      end
      ReportingEvent.create!(account: account, inbox: inbox, name: 'conversation_resolved', value: 600, created_at: 1.day.ago)
      ReportingEvent.create!(account: account, inbox: inbox, name: 'first_response', value: 999, created_at: 30.days.ago - 1.second)
      ReportingEvent.create!(account: account, inbox: inbox, name: 'first_response', value: 999, created_at: 1.day.from_now)
      ReportingEvent.create!(account: account, inbox: other_inbox, name: 'first_response', value: 999, created_at: 1.day.ago)
      ReportingEvent.create!(account: foreign, inbox: foreign_inbox, name: 'conversation_resolved', value: 999, created_at: 1.day.ago)

      get url, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['metrics']).to include(
        'window' => { 'since' => '2026-10-05T12:00:00Z', 'until' => '2026-11-04T12:00:00Z' },
        'conversations_count' => 2, 'avg_first_response_time' => 60.0, 'avg_resolution_time' => 600.0,
        'first_response_sample_count' => 2, 'resolution_sample_count' => 1
      )
    end
  end

  it 'returns configured queues in priority order only to an administrator' do
    first = create(:team, account: account, allow_auto_assign: true, name: 'Zulu')
    second = create(:team, account: account, allow_auto_assign: true, name: 'Alpha')
    create(:team, account: account, allow_auto_assign: true, name: 'Unselected queue')
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, enabled: true,
                                                 mode: 'priority', team_ids: [first.id, second.id], max_open: 3)

    get url, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['policy']).to include('enabled' => true, 'mode' => 'priority', 'max_open' => 3)
    expect(response.parsed_body['teams']).to eq([{ 'id' => first.id, 'name' => first.reload.name },
                                              { 'id' => second.id, 'name' => second.reload.name }])
  end

  it 'hides report metrics and queue configuration from an authorized operator without reporting permission' do
    create(:inbox_member, inbox: inbox, user: agent)
    team = create(:team, account: account, allow_auto_assign: true, name: 'Private queue')
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, enabled: true,
                                                 mode: 'direct', team_ids: [team.id], max_open: 3)

    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('inbox_id' => inbox.id, 'name' => inbox.name, 'metrics' => nil, 'policy' => nil, 'teams' => [])
    expect(response.body).not_to include(team.name, 'synthetic-not-used', 'broker.example.test')
  end

  it 'denies an operator immediately after inbox membership is revoked' do
    member = create(:inbox_member, inbox: inbox, user: agent)
    member.destroy!

    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
  end

  it 'denies an unassigned operator' do
    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects a foreign inbox even when the administrator belongs to both accounts' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: admin, role: :administrator)
    foreign_inbox = create(:channel_api, account: foreign).inbox

    get url.sub("/inboxes/#{inbox.id}/", "/inboxes/#{foreign_inbox.id}/"), headers: admin.create_new_auth_token

    expect(response).to have_http_status(:not_found)
  end

  it 'rejects arbitrary report-window parameters and feature-disabled access' do
    get url, headers: admin.create_new_auth_token, params: { since: 0 }
    expect(response).to have_http_status(:bad_request)

    account.disable_features!('jrc_broker')
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
