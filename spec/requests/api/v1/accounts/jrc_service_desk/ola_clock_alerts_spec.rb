# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Durable internal OLA alerts and scoped metrics', type: :request do
  include_context 'JRC Service Desk domain'
  include ActiveSupport::Testing::TimeHelpers
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit) }
  let(:ticket) { sd_ticket(queue: queue, assignee_membership: sd_membership) }
  let(:attributes) do
    { ola_targets: { 'first_response' => 60, 'update' => 120, 'resolution' => 600 }, ola_time_basis: 'calendar',
      ola_escalation_policy: { 'enabled' => true, 'thresholds' => [{ 'percent' => 50, 'queue_id' => nil, 'team_id' => nil,
                                                                     'notification_member_ids' => [sd_account_user.id], 'notification_channels' => %w[in_app email] }] } }
  end

  before do
    sd_as_admin!
    allow(JrcServiceDesk::ClockAlertMailer).to receive(:delivery_method).and_return(:test)
  end

  # Mail delivery uses Rails' test adapter. Declare the configured SMTP state
  # explicitly so preference/uncertain-result cases do not depend on local ENV.
  around { |example| with_modified_env(SMTP_ADDRESS: 'smtp.example.test') { example.run } }

  def observe
    travel_to(Time.utc(2026, 10, 24, 10)) do
      JrcServiceDesk::ConfigurationService.new(user_context: sd_context).update(resource: 'queues', record_id: queue.id,
                                                                                attributes: attributes, expected_revision: JrcServiceDesk::ConfigurationResources.revision('queues', queue), idempotency_key: SecureRandom.uuid)
      queue.reload
      JrcServiceDesk::OlaTracker.sync!(ticket)
      travel 31.seconds
      2.times { JrcServiceDesk::EvaluateClocksService.new(user_context: sd_context).call(ticket_id: ticket.id) }
    end
    JrcServiceDesk::ClockAlertDelivery.where(ticket: ticket).order(:id)
  end
  it 'records a threshold and its explicit channel/recipient intents once, without marking queued as delivered' do
    rows = observe
    expect(rows.count).to eq(2)
    expect(rows.pluck(:channel).sort).to eq(%w[email in_app])
    expect(rows.pluck(:state).uniq).to eq(['queued'])
    expect(ticket.ticket_events.where(event_type: 'clock_threshold_reached').count).to eq(1)
    expect(rows.pluck(:accepted_at)).to eq([nil, nil])
  end

  it 'persists a native bell notification once and links its authorized ticket without creating a conversation' do
    row = observe.find_by!(channel: 'in_app')
    count = Conversation.count
    2.times { JrcServiceDesk::ClockAlertJob.perform_now(row.id) }
    expect(row.reload.state).to eq('accepted')
    expect(row.notification).to have_attributes(user_id: sd_user.id, primary_actor_id: ticket.id, notification_type: 'service_desk_clock')
    expect(Notification.where(notification_type: 'service_desk_clock', primary_actor_id: ticket.id).count).to eq(1)
    expect(Conversation.count).to eq(count)
  end

  it 'blocks email without explicit native profile preference and permits a reasoned authorized retry after opt-in' do
    row = observe.find_by!(channel: 'email')
    setting = NotificationSetting.find_or_create_by!(account: sd_account, user: sd_user)
    setting.update!(email_service_desk_clock: false)
    JrcServiceDesk::ClockAlertJob.perform_now(row.id)
    expect(row.reload).to have_attributes(state: 'blocked', reason: 'recipient_preference', attempts: 0)
    setting.update!(email_service_desk_clock: true)
    post "#{root}/automation_insights/clock_alerts/retry", headers: headers, as: :json,
                                                           params: { unit_id: sd_unit.id, alert_id: row.id, expected_attempts: 0, reason: 'Synthetic recipient opted in' }
    expect(response).to have_http_status(:ok), response.body
    JrcServiceDesk::ClockAlertJob.perform_now(row.id)
    expect(row.reload).to have_attributes(state: 'accepted', reason: 'smtp_accepted_not_delivery_confirmation', attempts: 1)
    expect(ticket.ticket_events.where(event_type: 'resource_updated').where("data->>'clock_alert_retry_id' = ?", row.id.to_s).count).to eq(1)
  end

  it 'blocks a queued alert after the current queue policy is changed, preserving its historical threshold' do
    row = observe.find_by!(channel: 'in_app')
    previous = row.ticket_event.data.deep_dup
    JrcServiceDesk::ConfigurationService.new(user_context: sd_context).update(resource: 'queues', record_id: queue.id,
                                                                              attributes: { name: 'Republished queue' }, expected_revision: JrcServiceDesk::ConfigurationResources.revision('queues', queue.reload), idempotency_key: SecureRandom.uuid)
    JrcServiceDesk::ClockAlertJob.perform_now(row.id)
    expect(row.reload).to have_attributes(state: 'blocked', reason: 'publication_changed')
    expect(row.ticket_event.reload.data).to eq(previous)
  end

  it 'hides existing native alerts when Service Desk permission is revoked' do
    row = observe.find_by!(channel: 'in_app')
    JrcServiceDesk::ClockAlertJob.perform_now(row.id)
    expect(JrcServiceDesk::ClockAlerts.visible?(row.reload.notification)).to be(true)
    sd_account.disable_features!('jrc_service_desk')
    expect(JrcServiceDesk::ClockAlerts.visible?(row.notification)).to be(false)
    put "/api/v1/accounts/#{sd_account.id}/notifications/#{row.notification_id}", headers: headers, as: :json,
                                                                                  params: { read_at: Time.current.iso8601 }
    expect(response).to have_http_status(:not_found)
  end

  it 'does not automatically repeat an uncertain SMTP result and refuses an HTTP retry' do
    row = observe.find_by!(channel: 'email')
    NotificationSetting.find_or_create_by!(account: sd_account, user: sd_user).update!(email_service_desk_clock: true)
    allow(JrcServiceDesk::ClockAlertMailer).to receive(:with).and_raise(IOError, 'synthetic unknown provider effect')
    2.times { JrcServiceDesk::ClockAlertJob.perform_now(row.id) }
    expect(row.reload).to have_attributes(state: 'unknown', attempts: 1)
    post "#{root}/automation_insights/clock_alerts/retry", headers: headers, as: :json,
                                                           params: { unit_id: sd_unit.id, alert_id: row.id, expected_attempts: 1, reason: 'Must be denied' }
    expect(response).to have_http_status(:conflict)
    expect(row.reload.state).to eq('unknown')
  end

  it 'returns authorized period/assignee metrics, daily evolution and exports only the same filtered records' do
    observe
    get "#{root}/automation_insights/ola", headers: headers,
                                           params: { unit_id: sd_unit.id, queue_id: queue.id, days: 90, assignee_account_user_id: sd_account_user.id, export: 'true' }
    expect(response).to have_http_status(:ok), response.body
    payload = response.parsed_body
    expect(payload['total']).to eq(3)
    expect(payload['items'].map { |item| item['metric_kind'] }.sort).to eq(%w[first_response resolution update])
    expect(payload['daily'].values.flat_map(&:values).sum).to eq(3)
    expect(payload['measurements'].keys.sort).to eq(%w[first_response resolution update])
    get "#{root}/automation_insights/clock_alerts", headers: headers, params: { unit_id: sd_unit.id, queue_id: queue.id, days: 90 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['total']).to eq(2)
    get "#{root}/automation_insights/ola", headers: headers, params: { unit_id: sd_foreign_unit.id, days: 90 }
    expect(response).to have_http_status(:not_found)
  end

  context 'with explicit departmental supervision' do
    let(:team) { create(:team, account: sd_account) }
    let(:queue) { create(:jrc_sd_queue, unit: sd_unit, team: team) }
    let(:ticket) { sd_ticket(queue: queue, team: team, assignee_membership: sd_membership) }

    before { create(:team_member, team: team, user: sd_user) }

    it 'blocks emission, mail rendering and OLA metrics when ticket visibility has no explicit SLA grant' do
      rows = observe
      sd_membership.update!(restricted_supervision: true, supervision_grants: [{ queue_id: queue.id, team_id: team.id,
        permissions: %w[tickets_view tickets_edit] }])
      expect(JrcServiceDesk::TicketPolicy.new(sd_context, ticket).show?).to be(true)
      expect(JrcServiceDesk::OperationalContext.new(sd_context).capability?(:sla_view)).to be(true)
      row = rows.find_by!(channel: 'in_app')
      expect(JrcServiceDesk::ClockAlerts.blocker(row)).to eq('authority_revoked')
      expect { JrcServiceDesk::ClockAlertJob.perform_now(row.id) }.not_to change(Notification, :count)
      expect(row.reload).to have_attributes(state: 'blocked', reason: 'authority_revoked')
      email = rows.find_by!(channel: 'email')
      expect { JrcServiceDesk::ClockAlertMailer.with(account: sd_account).alert(email.id).message }.to raise_error(Pundit::NotAuthorizedError)

      %w[ola clock_alerts].each do |kind|
        get "#{root}/automation_insights/#{kind}", headers: headers, params: { unit_id: sd_unit.id, days: 90 }
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.fetch('total')).to eq(0)
        expect(response.parsed_body.fetch('items')).to be_empty
      end
    end

    it 'hides existing bell notifications and counts immediately after revoking only the SLA operation grant' do
      sd_membership.update!(restricted_supervision: true, supervision_grants: [{ queue_id: queue.id, team_id: team.id,
        permissions: %w[tickets_view tickets_edit sla_view] }])
      row = observe.find_by!(channel: 'in_app')
      JrcServiceDesk::ClockAlertJob.perform_now(row.id)
      notification = row.reload.notification
      expect(JrcServiceDesk::ClockAlerts.visible?(notification)).to be(true)
      expect(NotificationFinder.new(sd_user, sd_account).notifications.where(id: notification.id)).to exist

      sd_membership.update!(supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: %w[tickets_view tickets_edit] }])
      expect(JrcServiceDesk::TicketPolicy.new(sd_context, ticket).show?).to be(true)
      expect(JrcServiceDesk::ClockAlerts.visible?(notification)).to be(false)
      finder = NotificationFinder.new(sd_user, sd_account)
      expect(finder.notifications.where(id: notification.id)).not_to exist
      expect(finder.count).to eq(0)
      expect(finder.unread_count).to eq(0)
      put "/api/v1/accounts/#{sd_account.id}/notifications/#{notification.id}", headers: headers, as: :json,
        params: { read_at: Time.current.iso8601 }
      expect(response).to have_http_status(:not_found)
    end

    it 'rechecks a recipient SLA grant independently of the authorized execution actor' do
      recipient = create(:account_user, account: sd_account, role: :agent)
      recipient_membership = create(:jrc_sd_membership, unit: sd_unit, account_user: recipient, restricted_supervision: true,
        supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: %w[tickets_view sla_view] }])
      attributes[:ola_escalation_policy]['thresholds'][0]['notification_member_ids'] = [recipient.id]
      row = observe.find_by!(channel: 'in_app')
      expect(JrcServiceDesk::ClockAlerts.blocker(row)).to be_nil
      recipient_membership.update!(supervision_grants: [{ queue_id: queue.id, team_id: team.id, permissions: ['tickets_view'] }])
      expect(JrcServiceDesk::ClockAlerts.blocker(row)).to eq('recipient_revoked')
      expect { JrcServiceDesk::ClockAlertJob.perform_now(row.id) }.not_to change(Notification, :count)
      expect(row.reload).to have_attributes(state: 'blocked', reason: 'recipient_revoked')
    end
  end
end
