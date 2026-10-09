# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, :with_email, account: sd_account) }

  include JrcServiceDeskConcurrency

  def event_fixture
    sd_as_admin!
    ticket = sd_ticket
    channel = create(:channel_email, account: sd_account, email: "r2-#{SecureRandom.uuid}@example.test",
                                     forward_to_email: "r2-forward-#{SecureRandom.uuid}@example.test",
                                     smtp_enabled: true, smtp_address: 'smtp.test.invalid', smtp_port: 587)
    conversation = create(:conversation, account: sd_account, inbox: channel.inbox, contact: sd_contact)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context).call(
      unit_id: sd_unit.id,
      attributes: { event_type: 'ticket_created', channel: 'email', enabled: true, confirmed: true, inbox_id: channel.inbox.id,
                    template: '{{number}} {{title}}', template_version: 'r2-concurrency' }
    )
    JrcServiceDesk::TicketEvent.create!(account: sd_account, unit: sd_unit, ticket: ticket, actor_membership: sd_membership,
                                        event_type: 'ticket_created', visibility: 'internal', data: {})
  end

  it 'persists one approved event intent under two simultaneous jobs' do
    source = event_fixture
    identifier = source.id
    outcomes = concurrently(Array.new(2) do
      lambda {
        JrcServiceDesk::NotificationEngine.new(JrcServiceDesk::TicketEvent.find(identifier)).call.map(&:id)
      }
    end)
    expect(outcomes).to all(be_an(Array))
    expect(outcomes.uniq.size).to eq(1)
    expect(JrcServiceDesk::NotificationDelivery.where(ticket_event_id: identifier).count).to eq(1)
  end

  it 'persists one manually reviewed retry attempt for a shared idempotency key under concurrent commands' do
    source = event_fixture
    original = JrcServiceDesk::NotificationEngine.new(source).call.first
    original.update!(state: 'failed', reason: 'provider_failure')
    native_context = sd_context
    review = JrcServiceDesk::NotificationResendPreview.new(
      row: original, context: JrcServiceDesk::OperationalContext.new(native_context)
    ).call(reason: 'Explicit controlled repeat')
    identifier = original.id
    outcomes = concurrently(Array.new(2) do
      lambda {
        JrcServiceDesk::ResendNotificationService.new(user_context: native_context).call(
          delivery: JrcServiceDesk::NotificationDelivery.find(identifier), receipt: review.fetch(:receipt),
          reason: review.fetch(:reason), idempotency_key: 'r2-concurrent-resend'
        ).id
      }
    end)
    expect(outcomes).to all(be_an(Integer))
    expect(outcomes.uniq.size).to eq(1)
    expect(JrcServiceDesk::NotificationDelivery.where(original_delivery_id: identifier).pluck(:attempt_number)).to eq([2])
    expect(source.ticket.ticket_notes).to be_empty
  end
end
