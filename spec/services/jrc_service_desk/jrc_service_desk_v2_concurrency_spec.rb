# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, :with_email, account: sd_account) }

  include JrcServiceDeskConcurrency

  it 'serializes two claims by one agent without exceeding capacity' do
    sd_membership.update!(availability: 'available', capacity: 1)
    tickets = [sd_ticket, sd_ticket]
    context = sd_context
    unit_id = sd_unit.id
    outcomes = concurrently(Array.new(2) do |number|
      lambda {
        JrcServiceDesk::ClaimNextService.new(user_context: context).call(unit_id: unit_id, idempotency_key: "claim-#{number}").id
      }
    end)
    expect(outcomes.count { |result| result.is_a?(Integer) }).to eq(1)
    expect(outcomes.count { |result| result.is_a?(JrcServiceDesk::LifecycleDependencyError) }).to eq(1)
    expect(JrcServiceDesk::Ticket.where(id: tickets.map(&:id), assignee_membership_id: sd_membership.id).count).to eq(1)
  end

  it 'gives two eligible agents different tickets under simultaneous claim' do
    sd_membership.update!(availability: 'available', capacity: 1)
    other = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: other, availability: 'available', capacity: 1)
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    create(:team_member, team: team, user: other.user)
    tickets = [sd_ticket(team: team), sd_ticket(team: team)]
    contexts = [sd_context, { account: sd_account, user: other.user, account_user: other }]
    unit_id = sd_unit.id
    outcomes = concurrently(contexts.each_with_index.map do |context, number|
      lambda {
        JrcServiceDesk::ClaimNextService.new(user_context: context).call(unit_id: unit_id, idempotency_key: "agent-#{number}").id
      }
    end)
    expect(outcomes.sort).to eq(tickets.map(&:id).sort)
    expect(tickets.map { |ticket| ticket.reload.assignee_membership_id }.sort).to eq([sd_membership.id, grant.id].sort)
  end

  def notification_fixture
    sd_as_admin!
    ticket = sd_ticket
    channel = notification_channel
    conversation = create(:conversation, account: sd_account, inbox: channel.inbox, contact: sd_contact)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    notification_policy(channel)
    note = notification_note(ticket, conversation)
    JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: note.id)
  end

  def notification_channel
    create(:channel_email, account: sd_account, email: "sd-#{SecureRandom.uuid}@example.test",
                           forward_to_email: "sd-forward-#{SecureRandom.uuid}@example.test",
                           smtp_enabled: true, smtp_address: 'smtp.test.invalid', smtp_port: 587)
  end

  def notification_policy(channel)
    JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context).call(
      unit_id: sd_unit.id,
      attributes: { channel: 'email', enabled: true, confirmed: true, inbox_id: channel.inbox.id,
                    template: '{{body}}', template_version: 'test-v1' }
    )
  end

  def notification_note(ticket, conversation)
    attributes = { body: 'Concurrent controlled notification', visibility: 'customer', notification_channels: ['email'],
                   notification_conversations: { 'email' => conversation.id } }
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    receipt = JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: attributes).fetch(:receipt)
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: attributes,
                                                                      preview_receipt: receipt, idempotency_key: 'concurrent-delivery')
  end

  it 'creates only one native message for two simultaneous delivery-builder jobs' do
    row = notification_fixture
    delivery_id = row.id
    outcomes = concurrently(Array.new(2) do
      lambda {
        JrcServiceDesk::NotificationDeliveryJob.perform_now(delivery_id)
        true
      }
    end)
    expect(outcomes).to eq([true, true])
    row.reload
    messages = Message.where(account_id: sd_account.id).select do |message|
      message.content_attributes['service_desk_delivery_id'].to_s == row.id.to_s
    end
    expect(messages.size).to eq(1)
    expect(row.message_id).to eq(messages.first.id)
  end

  it 'crosses the provider boundary once for two simultaneous native send jobs' do
    row = notification_fixture
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    message_id = row.reload.message_id
    provider_calls = Queue.new
    outcomes = concurrently(Array.new(2) do
      lambda {
        message = Message.find(message_id)
        JrcServiceDesk::NotificationExecution.new(message).perform do
          provider_calls << true
          message.update!(source_id: 'test-concurrent-provider-id')
        end
        true
      }
    end)
    expect(outcomes).to eq([true, true])
    expect(provider_calls.size).to eq(1)
    expect(row.reload.state).to eq('sent')
    expect(row.provider_id).to eq('test-concurrent-provider-id')
  end
end
