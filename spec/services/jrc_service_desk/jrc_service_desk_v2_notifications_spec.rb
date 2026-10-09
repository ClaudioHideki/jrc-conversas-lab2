# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers
  let(:sd_contact) { create(:contact, :with_email, account: sd_account) }
  let(:ticket) { sd_ticket }
  let(:email_channel) { create(:channel_email, account: sd_account, smtp_enabled: true, smtp_address: 'smtp.test.invalid', smtp_port: 587) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: email_channel.inbox, contact: sd_contact) }

  before do
    sd_as_admin!
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  def policy(enabled: true)
    JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context).call(
      unit_id: sd_unit.id,
      attributes: { channel: 'email', enabled: enabled, confirmed: true, inbox_id: email_channel.inbox.id,
                    template: 'Ticket {{number}}: {{body}}', template_version: 'test-v1' }
    )
  end

  def note
    attributes = { body: 'Customer update for isolated tests', visibility: 'customer', notification_channels: ['email'],
                   notification_conversations: { 'email' => conversation.id } }
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    receipt = JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: attributes).fetch(:receipt)
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: attributes,
                                                                      preview_receipt: receipt, idempotency_key: 'test-customer-update')
  end

  def queued_delivery
    policy
    publication = note
    row = JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: publication.id)
    expect(row.state).to eq('queued'), "Delivery blocked: #{row.reason}"
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    row.reload
  end

  it 'records an explicit blocked dependency without creating native messages when no policy exists' do
    publication = nil
    expect { publication = note }.not_to change(Message, :count)
    row = JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: publication.id)
    expect(row.attributes.values_at('state', 'reason', 'message_id')).to eq(['blocked', 'policy_disabled', nil])
  end

  it 'deduplicates channel intent on replay without an additional delivery or message' do
    publication = note
    expect { note }.not_to change(JrcServiceDesk::NotificationDelivery, :count)
    expect(JrcServiceDesk::NotificationDelivery.where(ticket_note_id: publication.id).count).to eq(1)
  end

  it 'requires current approved configuration and reports missing SMTP explicitly' do
    policy
    email_channel.update!(smtp_enabled: false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMTP_ADDRESS').and_return(nil)
    row = JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: note.id)
    expect(row.attributes.values_at('state', 'reason')).to eq(%w[blocked smtp_unavailable])
    expect(row.message_id).to be_nil
  end

  it 'requires an actual customer email and does not guess a notification recipient' do
    policy
    sd_contact.update!(email: nil)
    row = JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: note.id)
    expect(row.attributes.values_at('state', 'reason', 'recipient', 'message_id')).to eq(['blocked', 'recipient_missing', nil, nil])
  end

  it 'uses the native builder with an explicit recipient and binds one native message to the delivery' do
    row = queued_delivery
    expect(row.message.outgoing?).to be(true)
    expect(row.message.private?).to be(false)
    expect(row.message.sender).to be_nil
    expect(row.message.content_attributes['to_emails']).to eq([sd_contact.email])
    expect(row.message.content).to eq("Ticket #{ticket.id}: Customer update for isolated tests")
    expect(row.payload_digest).to eq(JrcServiceDesk::NotificationExecution.payload_digest(row.message, row))
    expect { JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id) }.not_to change(Message, :count)
  end

  it 'calls the existing native channel boundary in controlled tests and preserves provider source ID' do
    row = queued_delivery
    provider = instance_double(Email::SendOnEmailService)
    allow(Email::SendOnEmailService).to receive(:new).with(message: row.message).and_return(provider)
    expect(provider).to receive(:perform) { row.message.update!(source_id: 'test-provider-accepted') }
    SendReplyJob.perform_now(row.message_id)
    expect(row.reload.state).to eq('sent')
    expect(row.provider_id).to eq('test-provider-accepted')
    expect(row.sent_at).to be_present
    expect(provider).not_to receive(:perform)
    SendReplyJob.perform_now(row.message_id)
  end

  it 'reconciles delivered/read only from native receipt state without inventing delivery' do
    row = queued_delivery
    JrcServiceDesk::NotificationExecution.new(row.message).perform { row.message.update!(source_id: 'test-receipt') }
    row.message.update!(status: :delivered)
    JrcServiceDesk::NotificationReconciliationJob.perform_now(row.message_id)
    expect(row.reload.state).to eq('delivered')
    expect(row.delivered_at).to be_present
    row.message.update!(status: :read)
    JrcServiceDesk::NotificationReconciliationJob.perform_now(row.message_id)
    expect(row.reload.state).to eq('read')
  end

  it 'resolves a duplicate in-flight unknown result from the original native provider evidence without sending twice' do
    row = queued_delivery
    message = row.message
    called = 0
    JrcServiceDesk::NotificationExecution.new(message).perform do
      called += 1
      JrcServiceDesk::NotificationExecution.new(Message.find(message.id)).perform { called += 1 }
      expect(row.reload.state).to eq('unknown')
      message.update!(source_id: 'test-original-provider-result')
    end
    expect(called).to eq(1)
    expect(row.reload.state).to eq('sent')
    expect(row.provider_id).to eq('test-original-provider-result')
    expect { |block| JrcServiceDesk::NotificationExecution.new(message).perform(&block) }.not_to yield_control
  end

  it 'keeps a real read receipt that reconciles before the original execution finishes' do
    row = queued_delivery
    message = row.message
    JrcServiceDesk::NotificationExecution.new(message).perform do
      message.update!(source_id: 'test-concurrent-read-receipt', status: :read)
      JrcServiceDesk::NotificationReconciliationJob.perform_now(message.id)
    end
    expect(row.reload.state).to eq('read')
    expect(row.provider_id).to eq('test-concurrent-read-receipt')
    expect(row.delivered_at).to be_present
  end

  it 'preserves an uncertain original call after a duplicate increments the delivery version and never retries it' do
    row = queued_delivery
    called = 0
    JrcServiceDesk::NotificationExecution.new(row.message).perform do
      called += 1
      JrcServiceDesk::NotificationExecution.new(Message.find(row.message_id)).perform { called += 1 }
      raise Timeout::Error, 'remote sensitive error'
    end
    expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
    expect(called).to eq(1)
    expect(row.reload.attributes.values_at('state', 'reason')).to eq(%w[unknown provider_result_unknown])
  end

  it 'preserves unknown provider result and never retries the native boundary after uncertainty' do
    row = queued_delivery
    called = 0
    execution = lambda {
      JrcServiceDesk::NotificationExecution.new(row.message).perform do
        called += 1
        raise Timeout::Error, 'remote sensitive error'
      end
    }
    execution.call
    execution.call
    expect(called).to eq(1)
    expect(row.reload.attributes.values_at('state', 'reason')).to eq(%w[unknown provider_result_unknown])
    expect(row.reason).not_to include('sensitive')
  end

  it 'does not infer sent or delivered from the native default sent status' do
    row = queued_delivery
    JrcServiceDesk::NotificationExecution.new(row.message).perform { nil }
    expect(row.reload.attributes.values_at('state', 'reason')).to eq(%w[unknown provider_result_unverified])
    expect(row.provider_id).to be_nil
  end

  it 'blocks when the approved policy is switched OFF after queuing' do
    row = queued_delivery
    policy(enabled: false)
    expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
    expect(row.reload.attributes.values_at('state', 'reason')).to eq(%w[blocked policy_disabled_or_changed])
  end

  it 'blocks a revoked operational grant immediately before provider execution' do
    row = queued_delivery
    sd_membership.update!(active: false)
    expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
    expect(row.reload.reason).to eq('authorization_revoked')
  end

  it 'rechecks a revocation occurring between the claim and the provider boundary' do
    row = queued_delivery
    checks = 0
    allow(JrcServiceDesk::NotificationEngine).to receive(:blocker).and_wrap_original do |original, candidate|
      checks += 1
      sd_membership.update!(active: false) if checks == 2
      original.call(candidate)
    end
    expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
    expect(checks).to eq(2)
    expect(row.reload.reason).to eq('authorization_revoked')
  end

  it 'rejects a recipient change instead of sending to a new address implicitly' do
    row = queued_delivery
    sd_contact.update!(email: 'another-recipient@example.com')
    expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
    expect(row.reload.reason).to eq('recipient_changed')
  end

  %w[content content_attributes additional_attributes].each do |field|
    it "blocks edited #{field} and sends no unapproved native payload" do
      row = queued_delivery
      value = field == 'content' ? 'Unapproved content' : row.message.public_send(field).merge('unapproved' => 'payload')
      row.message.update!(field => value)
      expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
      expect(row.reload.reason).to eq('message_payload_changed')
    end
  end

  it 'does not treat a public content identifier as authorization for a different native message' do
    row = queued_delivery
    forged = create(:message, account: sd_account, inbox: conversation.inbox, conversation: conversation,
                              message_type: :outgoing, content_attributes: { 'service_desk_delivery_id' => row.id })
    expect { |block| JrcServiceDesk::NotificationExecution.new(forged).perform(&block) }.not_to yield_control
    expect(row.reload.state).to eq('queued')
  end

  it 'rejects simultaneous delivery controllers even if their altered payload digest is recomputed' do
    row = queued_delivery
    row.message.update!(content_attributes: row.message.content_attributes.merge('nico_delegation' => true))
    row.update!(payload_digest: JrcServiceDesk::NotificationExecution.payload_digest(row.message, row))
    expect { |block| JrcServiceDesk::NotificationExecution.new(row.message).perform(&block) }.not_to yield_control
    expect(row.reload.reason).to eq('incompatible_delivery_control')
  end

  it 'excludes native private messages from the email history selected by the existing mailer' do
    public_message = create(:message, account: sd_account, conversation: conversation, inbox: conversation.inbox, private: false,
                                      content: 'Customer history')
    create(:message, account: sd_account, conversation: conversation, inbox: conversation.inbox, private: true,
                     content: 'Private operational evidence')
    row = queued_delivery
    history = conversation.messages.chat.where('id < ?', row.message_id).last
    expect(history.id).to eq(public_message.id)
    expect(history.content).not_to include('Private operational evidence')
  end

  it 'records real first response only after native acceptance and preserves the resolution clock' do
    lc_publish(definition: lc_definition(tracked: true))
    lc_snapshot(ticket)
    row = queued_delivery
    expect(ticket.sla_cycles).to be_empty
    JrcServiceDesk::NativeResponseRecorder.new(row.message).call
    expect(ticket.sla_cycles).to be_empty
    JrcServiceDesk::NotificationExecution.new(row.message).perform { row.message.update!(source_id: 'test-first-response') }
    JrcServiceDesk::NativeResponseRecorder.new(row.message.reload).call
    clocks = ticket.sla_cycles.first.sla_clocks
    expect(clocks.find_by!(kind: 'first_response').state).to eq('completed')
    expect(clocks.find_by!(kind: 'resolution').state).to eq('running')
    expect do
      JrcServiceDesk::NativeResponseRecorder.new(row.message.reload).call
    end.not_to change(
      ticket.ticket_events.where(event_type: 'first_response_recorded'), :count
    )
    expect(ticket.ticket_events.where(event_type: 'first_response_recorded').count).to eq(1)
  end

  it 'preserves the receipt observation time when a delayed job follows a later content edit' do
    travel_to(ticket.opened_at + 1.minute) do
      lc_publish(definition: lc_definition(tracked: true))
      lc_snapshot(ticket)
      message = create(:message, account: sd_account, inbox: conversation.inbox, conversation: conversation,
                                 sender: sd_user, message_type: :outgoing, private: false, content: 'Human customer response')
      message.update!(source_id: 'test-native-receipt')
      evidence = JrcServiceDesk::NativeResponseRecorder.evidence(message.reload)
      observed = message.updated_at
      travel 1.hour
      message.update!(content: 'Corrected customer response')
      JrcServiceDesk::FirstResponseJob.perform_now(message.id, evidence)
      clock = ticket.sla_cycles.first.sla_clocks.find_by!(kind: 'first_response')
      expect(clock.achieved_at).to eq(observed)
      expect(clock.achieved_at).not_to eq(message.reload.updated_at)
    end
  end

  it 'does not treat a caller supplied source ID on native message creation as receipt evidence' do
    lc_publish(definition: lc_definition(tracked: true))
    lc_snapshot(ticket)
    message = create(:message, account: sd_account, inbox: conversation.inbox, conversation: conversation,
                               sender: sd_user, message_type: :outgoing, private: false, content: 'Unverified creation', source_id: 'caller-value')
    JrcServiceDesk::FirstResponseJob.perform_now(message.id)
    expect(ticket.sla_cycles).to be_empty
  end
end
