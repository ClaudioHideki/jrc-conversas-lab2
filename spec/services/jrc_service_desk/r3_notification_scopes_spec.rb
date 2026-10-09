# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::NotificationPolicySelector do
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, :with_email, account: sd_account) }
  let(:channel) { create(:channel_email, account: sd_account, smtp_enabled: true, smtp_address: 'smtp.test.invalid', smtp_port: 587) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: channel.inbox) }
  let(:type) { JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_unit, name: 'Request', code: 'request', active: true) }
  let(:service) { JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Support', code: 'support', active: true) }
  let(:ticket) { sd_ticket(ticket_type: type, service: service) }
  let(:note) { build(:jrc_sd_note, ticket: ticket, visibility: 'customer', notification_channels: ['email']) }
  let(:values) do
    { channel: 'email', enabled: true, confirmed: true, inbox_id: channel.inbox.id,
      template: '{{number}} {{body}}', template_version: 'r3-test' }
  end
  let(:publish) { JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context) }

  before do
    sd_as_admin!
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  it 'uses a more specific OFF version without falling back to a general ON policy' do
    publish.call(unit_id: sd_unit.id, attributes: values)
    specific = publish.call(unit_id: sd_unit.id, attributes: values.merge(ticket_type_id: type.id, service_id: service.id, enabled: false))
    expect(JrcServiceDesk::NotificationEngine.current_policy(note, 'email')).to eq(specific)
    expect(specific.enabled?).to be(false)
    expect(Message.where(conversation: conversation)).not_to exist
  end

  it 'versions independent scopes and permits explicit disabling of an inactive historical type' do
    general = publish.call(unit_id: sd_unit.id, attributes: values.merge(expected_version: 0))
    specific = publish.call(unit_id: sd_unit.id, attributes: values.merge(ticket_type_id: type.id, expected_version: 0))
    expect([general.version, specific.version]).to eq([1, 1])
    type.update!(active: false)
    disabled = publish.call(unit_id: sd_unit.id, attributes: values.merge(ticket_type_id: type.id, expected_version: 1, enabled: false))
    expect(disabled.version).to eq(2)
    expect(specific.reload.enabled?).to be(true)
    expect do
      publish.call(unit_id: sd_unit.id, attributes: values.merge(ticket_type_id: type.id, expected_version: 2))
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'requires a combined published policy when type and service have competing scopes' do
    publish.call(unit_id: sd_unit.id, attributes: values)
    publish.call(unit_id: sd_unit.id, attributes: values.merge(ticket_type_id: type.id))
    publish.call(unit_id: sd_unit.id, attributes: values.merge(service_id: service.id, enabled: false))
    expect(JrcServiceDesk::NotificationEngine.current_policy(note, 'email')).to be_nil
    exact = publish.call(unit_id: sd_unit.id, attributes: values.merge(ticket_type_id: type.id, service_id: service.id))
    expect(JrcServiceDesk::NotificationEngine.current_policy(note, 'email')).to eq(exact)
  end

  it 'does not select the first of several linked conversations for automatic events' do
    other = create(:conversation, account: sd_account, contact: sd_contact, inbox: channel.inbox)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: other)
    policy = publish.call(unit_id: sd_unit.id, attributes: values.merge(event_type: 'ticket_created'))
    event = create(:jrc_sd_event, ticket: ticket)
    expect(JrcServiceDesk::NotificationSource.new(event).conversation(policy, 'email')).to be_nil
  end

  it 'persists explicit recipient opt-out in the native contact and writes a native audit' do
    sd_contact.update!(custom_attributes: { 'unrelated_setting' => 'preserved' })
    command = JrcServiceDesk::ContactNotificationPreferences.new(user_context: sd_context)
    expect { command.call(ticket_id: ticket.id, channels: []) }.not_to change(Message, :count)
    expect(JrcServiceDesk::ContactNotificationPreferences.channels(sd_contact.reload)).to eq([])
    expect(sd_contact.custom_attributes['unrelated_setting']).to eq('preserved')
    audit = Audited::Audit.where(auditable: sd_contact).order(:id).last
    expect(JSON.parse(audit.comment).values_at('account_id', 'unit_id', 'membership_id')).to eq([sd_account.id, sd_unit.id, sd_membership.id])
    expect(audit.audited_changes['service_desk_notification_channels']).to eq([%w[email whatsapp], []])
  end

  it 'blocks opted-out dispatch and rechecks permission revocation before editing preferences' do
    policy = publish.call(unit_id: sd_unit.id, attributes: values)
    sd_contact.update!(custom_attributes: { 'service_desk_notification_channels' => ['whatsapp'] })
    row = JrcServiceDesk::NotificationDelivery.new(
      account: sd_account, unit: sd_unit, ticket: ticket, ticket_note: note,
      execution_membership: sd_membership, notification_policy_version: policy, conversation: conversation, channel: 'email'
    )
    expect(JrcServiceDesk::NotificationEligibility.new(row).blocker).to eq('recipient_preference')
    sd_account_user.update!(role: :agent)
    expect do
      JrcServiceDesk::ContactNotificationPreferences.new(user_context: sd_context).call(ticket_id: ticket.id, channels: ['email'])
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(sd_contact.reload.custom_attributes['service_desk_notification_channels']).to eq(['whatsapp'])
  end
end
