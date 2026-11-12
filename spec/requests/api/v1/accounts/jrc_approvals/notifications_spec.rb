require 'rails_helper'

RSpec.describe 'Native approval notification access', :approval_core, type: :request do
  self.use_transactional_tests = false
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:approver) { approval_actor(scope) }
  let(:rule) { approval_publish(scope, author, approval_definition([approver])) }
  let(:record) do
    rule
    approval_request(scope, author)
  end
  let(:notice) do
    event = JrcApprovals::AuditEvent.find_by!(request_id: record.id, event_type: 'request_created')
    JrcApprovals::NotificationProjection.new(event.id).call
    Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: record, notification_type: 'approval_event')
  end
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/notifications" }
  let(:headers) { approver.user.create_new_auth_token }

  it 'lists and reads a bounded native notification without returning raw metadata or user credentials' do
    notice.update!(meta: notice.meta.merge('secret' => 'Synthetic private token', 'snapshot' => { 'amount' => 123 }))
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'meta')).to include('unread_count' => 1, 'count' => 1)
    row = response.parsed_body.dig('data', 'payload').first
    expect(row).to include('notification_type' => 'approval_event', 'primary_actor_id' => record.id)
    expect(response.body).not_to include('Synthetic private token', 'snapshot', 'pubsub_token', approver.user.email)
    patch "#{url}/#{notice.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Synthetic private token', 'snapshot', 'pubsub_token')
    expect(notice.reload.read_at).to be_present
  end

  it 'removes revoked access from listing/counts and denies direct read, unread and snooze URLs' do
    id = notice.id
    approver.custom_role.update!(permissions: ['jrc_approvals_request_create'])
    get url, headers: headers, as: :json
    expect(response.parsed_body.dig('data', 'payload')).to eq([])
    expect(response.parsed_body.dig('data', 'meta')).to include('count' => 0, 'unread_count' => 0)
    patch "#{url}/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{url}/#{id}/unread", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{url}/#{id}/snooze", params: { snoozed_until: 1.hour.from_now.iso8601 }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'preserves native pagination after permission filtering' do
    rule
    18.times do |index|
      request = approval_request(scope, author, key: "notice-page-#{index}")
      source = JrcApprovals::AuditEvent.find_by!(request_id: request.id, event_type: 'request_created')
      JrcApprovals::NotificationProjection.new(source.id).call
    end
    get url, params: { page: 1 }, headers: headers, as: :json
    first = response.parsed_body.dig('data', 'payload').pluck('id')
    expect(first.size).to eq(15)
    get url, params: { page: 2 }, headers: headers, as: :json
    second = response.parsed_body.dig('data', 'payload').pluck('id')
    expect(second.size).to eq(3)
    expect(first & second).to eq([])
    expect(response.parsed_body.dig('data', 'meta', 'count')).to eq(18)
  end

  it 'does not allow a different tenant to use a known notification or primary actor id' do
    id = notice.id
    foreign = approval_scope
    member = approval_actor(foreign)
    other_headers = member.user.create_new_auth_token
    patch "/api/v1/accounts/#{foreign[:account].id}/notifications/#{id}", headers: other_headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "/api/v1/accounts/#{foreign[:account].id}/notifications/read_all",
         params: { primary_actor_type: 'JrcApprovals::Request', primary_actor_id: record.id }, headers: other_headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(notice.reload.read_at).to be_nil
  end
end
