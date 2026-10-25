# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native notification templates and authorized email copies', type: :request do
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, :with_email, account: sd_account, phone_number: '+15555550143') }
  let(:ticket) { sd_ticket(assignee_membership: sd_membership) }
  let(:approved) do
    { 'name' => 'synthetic_status', 'language' => 'en', 'category' => 'UTILITY', 'status' => 'APPROVED',
      'components' => [{ 'type' => 'BODY', 'text' => 'Ticket {{1}}: {{2}}' }] }
  end
  let(:channel) { create(:channel_whatsapp, account: sd_account, message_templates: [approved]) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: channel.inbox, contact: sd_contact) }
  let(:configuration) do
    JrcServiceDesk::NotificationWhatsappTemplate.choices(channel.inbox).first.except('text').tap do |value|
      value['params']['processed_params']['body'] = { '1' => '{{number}}', '2' => '{{status}}' }
    end
  end
  let(:settings) do
    { 'conditions' => { 'operator' => 'all', 'items' => [] }, 'channel_order' => ['whatsapp'],
      'multichannel_mode' => 'first_available', 'additional_contact_ids' => [], 'internal_copy_member_ids' => [],
      'window' => { 'enabled' => false }, 'outside_window' => 'defer', 'max_attempts' => 1, 'backoff_minutes' => 10,
      'whatsapp_template' => configuration }
  end
  let(:attributes) do
    { event_type: 'ticket_created', channel: 'whatsapp', enabled: true, confirmed: true, expected_version: 0,
      inbox_id: channel.inbox.id, template: 'Ticket {{number}}: {{status}}', template_version: 'synthetic-v1', settings: settings }
  end
  let(:publisher) { JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context) }
  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:event) { create(:jrc_sd_event, ticket: ticket) }
  let(:delivery) do
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    JrcServiceDesk::NotificationEventJob.perform_now(event.id)
    JrcServiceDesk::NotificationDelivery.find_by!(ticket_event: event)
  end

  before do
    sd_as_admin!
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook').to_return(status: 200, body: '{}',
                                                                                  headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: { waba_templates: [approved] }.to_json,
                                                                                   headers: { 'Content-Type' => 'application/json' })
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    create(:message, conversation: conversation, account: sd_account, message_type: :incoming, created_at: 3.days.ago)
    WebMock.reset_executed_requests!
  end

  it 'offers only supported cached approved templates through authorized HTTP without a provider request or secrets' do
    channel.update!(message_templates: [approved, approved.merge('name' => 'pending', 'status' => 'PENDING'),
                                        approved.merge('name' => 'media', 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, *approved['components']])])
    WebMock.reset_executed_requests!
    get "#{root}/notification_policies", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    choices = response.parsed_body.fetch('inboxes').find { |row| row['id'] == channel.inbox.id.to_s }.fetch('whatsapp_templates')
    expect(choices.map { |row| row.dig('params', 'name') }).to eq(['synthetic_status'])
    expect(response.body).not_to include('api_key', 'test_key', 'provider_config')
    expect(WebMock).not_to have_requested(:any, /whatsapp|360dialog|facebook/)
  end

  it 'publishes and rereads the exact approved identity without generating a message' do
    expect do
      post "#{root}/notification_policies", params: { unit_id: sd_unit.id, policy: attributes }, headers: headers, as: :json
      expect(response).to have_http_status(:created), response.body
    end.not_to change(Message, :count)
    get "#{root}/notification_policies", params: { unit_id: sd_unit.id }, headers: headers
    expect(response.parsed_body.fetch('policies').first.fetch('settings')).to eq(settings)
  end

  it 'uses the native parser and approved payload outside the reply window without claiming provider delivery' do
    expect(conversation.reload.can_reply?).to be(false)
    row = delivery
    expect(row.state).to eq('queued'), row.reason
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    message = row.reload.message
    expect(message.content).to eq("Ticket #{ticket.id}: #{ticket.status.name}")
    expect(message.additional_attributes.dig('template_params', 'processed_params',
                                             'body')).to eq({ '1' => ticket.id.to_s, '2' => ticket.status.name })
    expect(row.state).to eq('queued')
    expect(row.sent_at).to be_nil
  end

  it 'continues blocking free text outside the reply window' do
    settings.delete('whatsapp_template')
    expect(delivery).to have_attributes(state: 'blocked', reason: 'channel_unavailable', message_id: nil)
  end

  it 'blocks a revoked approval before preparing a message' do
    row = delivery
    channel.update!(message_templates: [approved.merge('status' => 'REJECTED')])
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    expect(row.reload).to have_attributes(state: 'blocked', message_id: nil)
  end

  it 'rechecks the pinned template again at the actual provider boundary' do
    row = delivery
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    channel.update!(message_templates: [approved.merge('components' => [{ 'type' => 'BODY', 'text' => 'Changed {{1}} {{2}}' }])])
    called = false
    JrcServiceDesk::NotificationExecution.new(row.reload.message).perform { called = true }
    expect(called).to be(false)
    expect(row.reload.state).to eq('blocked')
  end

  it 'refuses a copied template from another inbox before adding a version' do
    alien = create(:channel_whatsapp, account: sd_account, message_templates: [approved])
    settings['whatsapp_template'] = JrcServiceDesk::NotificationWhatsappTemplate.choices(alien.inbox).first.except('text')
    expect { publisher.call(unit_id: sd_unit.id, attributes: attributes) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(0)
  end

  it 'refuses unknown data substitutions and dynamic media parameters' do
    settings['whatsapp_template']['params']['processed_params']['body']['1'] = '{{secret}}'
    expect { publisher.call(unit_id: sd_unit.id, attributes: attributes) }.to raise_error(ArgumentError)
    settings['whatsapp_template']['params']['processed_params']['body']['1'] = '{{number}}'
    settings['whatsapp_template']['params']['processed_params']['header'] = { 'media_url' => 'https://blocked.invalid/private' }
    expect { publisher.call(unit_id: sd_unit.id, attributes: attributes) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(0)
  end

  it 'preserves and revalidates the template when a legacy editor omits settings' do
    publisher.call(unit_id: sd_unit.id, attributes: attributes)
    other = create(:channel_whatsapp, account: sd_account, message_templates: [approved])
    changed = attributes.except(:settings).merge(expected_version: 1, inbox_id: other.inbox.id)
    expect { publisher.call(unit_id: sd_unit.id, attributes: changed) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::NotificationPolicyVersion.count).to eq(1)
  end

  context 'optional assignee copy' do
    let(:channel) { create(:channel_email, account: sd_account, smtp_enabled: true, smtp_address: 'synthetic.invalid', smtp_port: 587) }
    let(:configuration) { nil }

    before do
      settings.delete('whatsapp_template')
      settings['channel_order'] = ['email']
      settings['copy_assignee'] = true
      attributes[:channel] = 'email'
    end

    it 'freezes the event assignee, deduplicates an explicit copy and sends through native email headers' do
      settings['internal_copy_member_ids'] = [sd_account_user.id]
      row = delivery
      ticket.update!(assignee_membership: nil)
      JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
      expect(row.reload.message.content_attributes['cc_emails']).to eq([sd_user.email])
      expect(row.source_snapshot['assignee_account_user_id']).to eq(sd_account_user.id)
    end

    it 'blocks a queued copy after the assignee loses native ticket access' do
      row = delivery
      sd_membership.update!(active: false)
      sd_account_user.update!(role: :agent)
      JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
      expect(row.reload).to have_attributes(state: 'blocked', message_id: nil)
    end
  end
end
