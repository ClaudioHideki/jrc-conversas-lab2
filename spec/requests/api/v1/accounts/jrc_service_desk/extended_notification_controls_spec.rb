# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native versioned notification controls', type: :request do
  include_context 'JRC Service Desk domain'
  include ActiveSupport::Testing::TimeHelpers
  let(:sd_contact) { create(:contact, :with_email, account: sd_account) }
  let(:ticket) { sd_ticket }
  let(:email) { create(:channel_email, account: sd_account, smtp_enabled: true, smtp_address: 'smtp.synthetic.invalid', smtp_port: 587) }
  let(:whatsapp) { create(:channel_twilio_sms, account: sd_account, medium: :whatsapp) }
  let(:email_conversation) { create(:conversation, account: sd_account, inbox: email.inbox, contact: sd_contact) }
  let(:wa_conversation) { create(:conversation, account: sd_account, inbox: whatsapp.inbox, contact: sd_contact) }
  let(:publisher) { JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context) }
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:controls) do
    { 'conditions' => { 'operator' => 'all', 'items' => [] }, 'channel_order' => %w[email whatsapp],
      'multichannel_mode' => 'first_available', 'additional_contact_ids' => [], 'internal_copy_member_ids' => [],
      'window' => { 'enabled' => false }, 'outside_window' => 'defer', 'max_attempts' => 1, 'backoff_minutes' => 10 }
  end
  let(:attributes) do
    { event_type: 'ticket_created', channel: 'email', enabled: true, confirmed: true, expected_version: 0,
      inbox_id: email.inbox.id, template: 'Synthetic {{number}} {{title}}', template_version: 'synthetic-v1',
      settings: controls, channel_configurations: {
        'email' => { inbox_id: email.inbox.id, template: 'Synthetic email {{number}}', template_version: 'synthetic-v1' },
        'whatsapp' => { inbox_id: whatsapp.inbox.id, template: 'Synthetic WhatsApp {{number}}', template_version: 'synthetic-v1' }
      }, expected_versions: { 'email' => 0, 'whatsapp' => 0 } }
  end

  before do
    sd_as_admin!
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: email_conversation)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: wa_conversation)
    create(:message, account: sd_account, conversation: wa_conversation, message_type: :incoming)
  end

  def evaluate
    event = create(:jrc_sd_event, ticket: ticket)
    JrcServiceDesk::NotificationEventJob.perform_now(event.id)
    JrcServiceDesk::NotificationDelivery.where(ticket_event: event).order(:id).to_a
  end

  it 'atomically publishes native channel versions via HTTP without sending a message or a survey' do
    expect do
      expect do
        post "#{root}/notification_policies", params: { unit_id: sd_unit.id, policy: attributes }, headers: headers, as: :json
        expect(response).to have_http_status(:created), response.body
      end.not_to change(Message, :count)
    end.not_to change(JrcRelationship::Survey, :count)
    rows = JrcServiceDesk::NotificationPolicyVersion.where(unit: sd_unit)
    expect(rows.pluck(:channel).sort).to eq(%w[email whatsapp])
    expect(rows.map(&:settings).uniq).to eq([controls])
  end

  it 'rolls back all channels when a sibling inbox is invalid' do
    invalid = attributes.deep_dup
    invalid[:channel_configurations]['whatsapp'][:inbox_id] = email.inbox.id
    expect { publisher.call(unit_id: sd_unit.id, attributes: invalid) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(0)
  end

  it 'atomically retires a deselected channel and refuses a stale sibling version' do
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    changed = attributes.deep_dup
    changed[:settings]['channel_order'] = ['email']
    changed[:channel_configurations].delete('whatsapp')
    changed[:expected_versions] = { 'email' => 1, 'whatsapp' => 1 }
    changed[:expected_version] = 1
    changed[:retired_channels] = ['whatsapp']
    publisher.call(unit_id: sd_unit.id, attributes: changed)
    latest = JrcServiceDesk::NotificationPolicyVersion.where(unit: sd_unit, channel: 'whatsapp').order(version: :desc).first!
    expect(latest.enabled).to be(false)
    expect(latest.version).to eq(2)
    count = JrcServiceDesk::NotificationPolicyVersion.count
    expect { publisher.call(unit_id: sd_unit.id, attributes: changed) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(count)
    expect(evaluate.map(&:channel)).to eq(['email'])
  end

  it 'uses only the first eligible channel per recipient and never treats queued as sent' do
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    rows = evaluate
    expect(rows.map(&:channel)).to eq(['email'])
    expect(rows.map(&:state)).to eq(['queued'])
    expect(rows.first.sent_at).to be_nil
  end

  it 'requires explicit fan-out to prepare both channels' do
    controls['multichannel_mode'] = 'all_explicit'
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    expect(evaluate.map(&:channel).sort).to eq(%w[email whatsapp])
  end

  it 'falls back before preparation when the preferred channel has no authorized linked conversation' do
    controls['channel_order'] = %w[whatsapp email]
    empty_channel = create(:channel_twilio_sms, account: sd_account, medium: :whatsapp)
    attributes[:channel_configurations]['whatsapp'][:inbox_id] = empty_channel.inbox.id
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    rows = evaluate
    expect(rows.select { |row| row.state == 'queued' }.map(&:channel)).to eq(['email'])
    expect(rows.find { |row| row.channel == 'whatsapp' }.state).to eq('blocked')
  end

  it 'evaluates AND/OR conditions on the frozen event values rather than a changed ticket' do
    second_priority = create(:jrc_sd_priority, unit: sd_unit)
    controls['conditions'] = { 'operator' => 'all', 'items' => [{ 'field' => 'priority_id', 'operator' => 'eq', 'value' => sd_priority.id.to_s }] }
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    event = create(:jrc_sd_event, ticket: ticket)
    ticket.update!(priority: second_priority)
    JrcServiceDesk::NotificationEventJob.perform_now(event.id)
    expect(JrcServiceDesk::NotificationDelivery.where(ticket_event: event, state: 'queued').count).to eq(1)
    expect(event.reload.data.dig('notification_context', 'priority_id')).to eq(sd_priority.id)
  end

  it 'does not generate a delivery for an unmatched conjunction' do
    other_priority = create(:jrc_sd_priority, unit: sd_unit)
    controls['conditions']['items'] = [{ 'field' => 'priority_id', 'operator' => 'eq', 'value' => other_priority.id.to_s }]
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    rows = evaluate
    expect(rows.map(&:state).uniq).to eq(['blocked'])
    expect(rows.map(&:reason).uniq).to eq(['conditions_not_matched'])
  end

  it 'permits a matching disjunction without weakening its other conditions' do
    other_priority = create(:jrc_sd_priority, unit: sd_unit)
    controls['conditions'] = { 'operator' => 'any', 'items' => [
      { 'field' => 'priority_id', 'operator' => 'eq', 'value' => other_priority.id.to_s },
      { 'field' => 'status_id', 'operator' => 'eq', 'value' => sd_status.id.to_s }
    ] }
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    expect(evaluate.map(&:state)).to eq(['queued'])
  end

  it 'prepares an additional explicitly linked contact in the same customer company' do
    company = create(:company, account: sd_account)
    sd_contact.update!(company_id: company.id)
    colleague = create(:contact, :with_email, account: sd_account, company_id: company.id)
    linked = create(:conversation, account: sd_account, inbox: email.inbox, contact: colleague)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: linked)
    controls['additional_contact_ids'] = [colleague.id]
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    expect(evaluate.select { |row| row.state == 'queued' }.map(&:recipient_contact_id).sort).to eq([sd_contact.id, colleague.id].sort)
  end

  it 'blocks another company even if its contact and conversation are visible to the administrator' do
    outsider = create(:contact, :with_email, account: sd_account, company: create(:company, account: sd_account))
    linked = create(:conversation, account: sd_account, inbox: email.inbox, contact: outsider)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: linked)
    controls['additional_contact_ids'] = [outsider.id]
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    row = evaluate.find { |delivery| delivery.recipient_contact_id == outsider.id && delivery.channel == 'email' }
    expect(row).to have_attributes(state: 'blocked', reason: 'recipient_denied')
    expect(row.message_id).to be_nil
  end

  it 'defers to an explicit calendar opening and prepares no message early' do
    travel_to(Time.utc(2026, 10, 24, 12)) do
      controls['window'] = { 'enabled' => true, 'timezone' => 'America/Sao_Paulo', 'conditions' => {
        'format' => JrcServiceDesk::SnapshotCalendar::VERSION, 'weekly' => (1..7).to_h do |day|
                                                                 [day.to_s, day<=5 ? [['08:00', '18:00']] : []]
                                                               end, 'holidays' => [], 'exceptions' => {}
      } }
      publisher.call(unit_id: sd_unit.id, attributes: attributes)
      row = evaluate.first
      expect(row.not_before).to eq(Time.utc(2026, 10, 26, 11))
      JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
      expect(row.reload.message_id).to be_nil
    end
  end

  it 'allows skipping outside the configured calendar without claiming delivery' do
    travel_to(Time.utc(2026, 10, 24, 12)) do
      controls['outside_window'] = 'skip'
      controls['window'] = { 'enabled' => true, 'timezone' => 'UTC', 'conditions' => {
        'format' => JrcServiceDesk::SnapshotCalendar::VERSION, 'weekly' => (1..7).to_h do |day|
                                                                 [day.to_s, day<=5 ? [['08:00', '18:00']] : []]
                                                               end, 'holidays' => [], 'exceptions' => {}
      } }
      publisher.call(unit_id: sd_unit.id, attributes: attributes)
      expect(evaluate.map(&:state).uniq).to eq(['blocked'])
    end
  end

  it 'bounds retries of a known failure, deduplicates the next attempt and never retries unknown effects' do
    controls['max_attempts'] = 3
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    row = evaluate.first
    row.update!(state: 'failed', reason: 'provider_failure')
    2.times { JrcServiceDesk::NotificationRetryJob.perform_now(row.id) }
    attempts = JrcServiceDesk::NotificationDelivery.where(ticket_event_id: row.ticket_event_id, channel: row.channel).order(:attempt_number)
    expect(attempts.pluck(:attempt_number)).to eq([1, 2])
    expect(attempts.last.not_before).to be >= 9.minutes.from_now
    attempts.last.update!(state: 'unknown')
    expect { JrcServiceDesk::NotificationRetryJob.perform_now(attempts.last.id) }.not_to change(JrcServiceDesk::NotificationDelivery, :count)
  end

  it 'uses only authorized Account users as internal email copies and freezes the headers at preparation' do
    controls['internal_copy_member_ids'] = [sd_account_user.id]
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    row = evaluate.first
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    expect(row.reload.message.content_attributes['cc_emails']).to eq([sd_user.email])
    expect(row.payload_digest).to eq(JrcServiceDesk::NotificationExecution.payload_digest(row.message, row))
  end

  it 'denies unauthorized HTTP publication and rejects SMS/foreign recipients without adding versions' do
    sd_account_user.update!(role: :agent)
    post "#{root}/notification_policies", params: { unit_id: sd_unit.id, policy: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    sd_as_admin!
    controls['channel_order'] = ['sms']
    expect { publisher.call(unit_id: sd_unit.id, attributes: attributes) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(0)
  end

  it 'freezes category and origin conditions, records a discarded decision, and never recursively renders customer text' do
    category = create(:jrc_sd_category, unit: sd_unit)
    ticket.update!(category: category, origin_channel: 'manual')
    controls['conditions'] =
      { 'operator' => 'all',
        'items' => [{ 'field' => 'category_id', 'operator' => 'eq', 'value' => category.id.to_s },
                    { 'field' => 'origin_channel', 'operator' => 'eq', 'value' => 'manual' }] }
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    event = create(:jrc_sd_event, ticket: ticket)
    ticket.update!(category: nil)
    expect(event.reload.data.dig('notification_context', 'origin_channel')).to eq('manual')
    JrcServiceDesk::NotificationEventJob.perform_now(event.id)
    expect(JrcServiceDesk::NotificationDelivery.where(ticket_event: event, state: 'queued').count).to eq(1)
    blocked = evaluate
    expect(blocked).not_to be_empty
    expect(blocked.map(&:reason).uniq).to eq(['conditions_not_matched'])
    expect(JrcServiceDesk::NotificationSource.render('{{body}} {{title}}',
                                                     { 'body' => '{{title}}', 'title' => 'Frozen title' })).to eq('{{title}} Frozen title')
    expect(JrcServiceDesk::NotificationPolicyVersion.last.code).to start_with('sdnotify:')
  end
end
