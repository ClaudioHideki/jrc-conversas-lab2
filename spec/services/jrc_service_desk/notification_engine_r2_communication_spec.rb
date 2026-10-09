# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::NotificationEngine do
  include_context 'JRC Service Desk domain'
  include ActiveSupport::Testing::TimeHelpers
  let(:sd_contact) { create(:contact, :with_email, account: sd_account) }
  let(:ticket) { sd_ticket }
  let(:email_channel) { create(:channel_email, account: sd_account, smtp_enabled: true, smtp_address: 'smtp.test.invalid', smtp_port: 587) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: email_channel.inbox, contact: sd_contact) }
  let(:context) { JrcServiceDesk::OperationalContext.new(sd_context) }
  let(:attributes) do
    { body: 'Exact customer publication', visibility: 'customer', notification_channels: ['email'],
      notification_conversations: { 'email' => conversation.id } }
  end

  before do
    sd_as_admin!
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  def publish_policy(event_type = 'customer_interaction', enabled: true)
    JrcServiceDesk::PublishNotificationPolicyService.new(user_context: sd_context).call(
      unit_id: sd_unit.id,
      attributes: { event_type: event_type, channel: 'email', enabled: enabled, confirmed: true, inbox_id: email_channel.inbox.id,
                    template: '{{number}} {{title}} {{body}} {{task_title}} {{task_status}}', template_version: 'r2-test' }
    )
  end

  def preview(values = attributes)
    JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: values)
  end

  def publish(receipt, values = attributes, key: 'r2-publication')
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: values, preview_receipt: receipt, idempotency_key: key
    )
  end

  def event(type, data = {})
    JrcServiceDesk::TicketEvent.create!(
      account: sd_account, unit: sd_unit, ticket: ticket, actor_membership: sd_membership,
      event_type: type, visibility: 'internal', data: data
    )
  end

  def delivery
    publish_policy
    note = publish(preview.fetch(:receipt))
    JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: note.id)
  end

  it 'shows the exact recipient, template and dependency while previewing without a write or native message' do
    publish_policy
    count = JrcServiceDesk::TicketNote.count
    result = nil
    expect { result = preview }.not_to change(Message, :count)
    expect(JrcServiceDesk::TicketNote.count).to eq(count)
    plan = result[:deliveries].first
    expect(plan[:recipient]).to eq(sd_contact.email)
    expect(plan[:content]).to include(attributes[:body], ticket.title)
    expect(plan[:reason]).to be_nil
    expect(result[:audience]).to eq('customer')
  end

  it 'preserves defaults OFF and reports dependency reasons without inferring successful delivery' do
    result = preview
    expect(result[:deliveries].first[:reason]).to eq('policy_disabled_or_changed')
    expect(result[:notification_available]).to be(false)
    note = publish(result.fetch(:receipt))
    expect(JrcServiceDesk::NotificationDelivery.find_by!(ticket_note_id: note.id).state).to eq('blocked')
    expect(Message.where(account: sd_account)).to be_empty
  end

  { body: JrcServiceDesk::PublicationPreviewError, visibility: ArgumentError, notification_conversations: ArgumentError }.each do |field, error|
    it "invalidates approval when #{field} changes" do
      publish_policy
      receipt = preview.fetch(:receipt)
      changed = attributes.merge(field => field == :notification_conversations ? {} : 'Unapproved')
      expect { publish(receipt, changed) }.to raise_error(error)
      expect(ticket.ticket_notes).to be_empty
    end
  end

  it 'invalidates a reviewed recipient or policy version rather than silently sending a changed payload' do
    publish_policy
    receipt = preview.fetch(:receipt)
    sd_contact.update!(email: 'review-required@example.test')
    expect { publish(receipt) }.to raise_error(JrcServiceDesk::PublicationPreviewError)
    receipt = preview.fetch(:receipt)
    publish_policy(enabled: false)
    expect { publish(receipt) }.to raise_error(JrcServiceDesk::PublicationPreviewError)
    expect(ticket.ticket_notes).to be_empty
  end

  it 'invalidates expired and tampered confirmations without persisting content' do
    receipt = preview.fetch(:receipt)
    expect { publish(receipt.reverse) }.to raise_error(JrcServiceDesk::PublicationPreviewError)
    travel 6.minutes
    expect { publish(receipt) }.to raise_error(JrcServiceDesk::PublicationPreviewError)
    expect(ticket.ticket_notes).to be_empty
  end

  it 'revalidates a revoked actor after preview and keeps legacy internal publication independent' do
    receipt = preview.fetch(:receipt)
    sd_membership.update!(active: false)
    expect { publish(receipt) }.to raise_error(ActiveRecord::RecordNotFound)
    sd_membership.update!(active: true)
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { body: 'Legacy internal note' }, idempotency_key: 'legacy'
    )
    expect(note.visibility).to eq('internal')
  end

  { 'ticket_created' => 'ticket_created', 'ticket_assigned' => 'ticket_assigned', 'ticket_claimed' => 'ticket_assigned',
    'approval_requested' => 'approval_requested', 'approval_decided' => 'approval_decided' }.each do |origin, notification|
    it "creates one deduplicated postcommit intent for approved #{origin}" do
      publish_policy(notification)
      row = event(origin)
      expect(JrcServiceDesk::NotificationDelivery.where(ticket_event_id: row.id)).to be_empty
      2.times { JrcServiceDesk::NotificationEventJob.perform_now(row.id) }
      deliveries = JrcServiceDesk::NotificationDelivery.where(ticket_event_id: row.id)
      expect(deliveries.count).to eq(1)
      expect(deliveries.first.state).to eq('queued')
      expect(deliveries.first.execution_membership_id).to eq(sd_membership.id)
      expect(deliveries.first.source_snapshot['body']).to eq('')
    end
  end

  { 'resolve' => 'resolved', 'close' => 'closed', 'reopen' => 'reopened', 'work_status' => 'status_changed',
    'resume' => 'status_changed', 'cancel' => 'status_changed' }.each do |action, notification|
    it "uses the approved event policy for lifecycle #{action}" do
      publish_policy(notification)
      row = event('lifecycle_transitioned', 'action' => action)
      JrcServiceDesk::NotificationEventJob.perform_now(row.id)
      expect(JrcServiceDesk::NotificationDelivery.where(ticket_event_id: row.id).pluck(:state)).to eq(['queued'])
    end
  end

  it 'publishes waiting-customer from the persisted lifecycle status, with no note body copied' do
    publish_policy('waiting_customer')
    waiting = create(:jrc_sd_status, unit: sd_unit, phase: 'waiting', initial: false)
    row = event('lifecycle_transitioned', 'action' => 'pause', 'to_status_id' => waiting.id, 'note' => 'Internal secret diagnosis')
    JrcServiceDesk::NotificationEventJob.perform_now(row.id)
    actual = JrcServiceDesk::NotificationDelivery.find_by!(ticket_event_id: row.id)
    expect(actual.source_snapshot.to_s).not_to include('Internal secret diagnosis')
    expect(actual.state).to eq('queued')
  end

  it 'keeps internal and silent events OFF even when a customer interaction policy is enabled' do
    publish_policy
    row = event('note_added', 'note_id' => 123)
    expect { JrcServiceDesk::NotificationEventJob.perform_now(row.id) }.not_to change(JrcServiceDesk::NotificationDelivery, :count)
    row = event('ticket_created')
    expect { JrcServiceDesk::NotificationEventJob.perform_now(row.id) }.not_to change(JrcServiceDesk::NotificationDelivery, :count)
  end

  it 'freezes the event fields before commit and does not notify historical events created while OFF' do
    historical = event('ticket_created')
    publish_policy('ticket_created')
    expect { JrcServiceDesk::NotificationEventJob.perform_now(historical.id) }.not_to change(JrcServiceDesk::NotificationDelivery, :count)
    current = event('ticket_created')
    original_title = ticket.title
    ticket.update!(title: 'Later edited operational title')
    JrcServiceDesk::NotificationEventJob.perform_now(current.id)
    row = JrcServiceDesk::NotificationDelivery.find_by!(ticket_event_id: current.id)
    expect(row.source_snapshot['title']).to eq(original_title)
    expect(row.source_snapshot['title']).not_to eq(ticket.reload.title)
  end

  it 'sends customer tasks only after explicit task visibility and approved completion policy' do
    publish_policy('task_completed')
    internal = JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { title: 'Internal source task' }, idempotency_key: 'internal-task'
    )
    internal_event = event('task_updated', 'task_id' => internal.id, 'changes' => { 'status' => %w[open completed] })
    expect { JrcServiceDesk::NotificationEventJob.perform_now(internal_event.id) }.not_to change(JrcServiceDesk::NotificationDelivery, :count)
    expect { internal.update!(visibility: 'customer') }.to raise_error(ActiveRecord::RecordInvalid)
    task = JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { title: 'Public verified task', visibility: 'customer' }, idempotency_key: 'public-task'
    )
    row = event('task_updated', 'task_id' => task.id, 'changes' => { 'status' => %w[open completed] })
    JrcServiceDesk::NotificationEventJob.perform_now(row.id)
    actual = JrcServiceDesk::NotificationDelivery.find_by!(ticket_event_id: row.id)
    expect(actual.source_snapshot['task_status']).to eq('completed')
    expect { task.update!(visibility: 'internal') }.to raise_error(ActiveRecord::RecordInvalid)
    expect(task.reload.visibility).to eq('customer')
    expect(JrcServiceDesk::NotificationSource.new(internal_event).publishable?).to be(false)
    internal_delivery = actual.dup
    internal_delivery.ticket_event = internal_event
    expect(described_class.blocker(internal_delivery)).to eq('visibility_not_customer')
  end

  it 'does not reconcile a native payload modified after approval or downgrade a real read receipt' do
    row = delivery
    JrcServiceDesk::NotificationDeliveryJob.perform_now(row.id)
    row.reload
    JrcServiceDesk::NotificationExecution.new(row.message).perform { row.message.update!(source_id: 'r2-native-receipt', status: :read) }
    JrcServiceDesk::NotificationReceipt.new(row.reload).call
    row.message.update!(status: :failed)
    JrcServiceDesk::NotificationReceipt.new(row.reload).call
    expect(row.reload.state).to eq('read')
    row.update!(state: 'unknown')
    row.message.update!(content: 'Unapproved evidence', status: :delivered)
    JrcServiceDesk::NotificationReceipt.new(row.reload).call
    expect(row.reload.state).to eq('unknown')
  end

  it 'creates a separately approved resend attempt without duplicating the immutable interaction' do
    row = delivery
    row.update!(state: 'failed', reason: 'provider_failure')
    review = JrcServiceDesk::NotificationResendPreview.new(row: row, context: context).call(reason: 'Customer requested another copy')
    command = JrcServiceDesk::ResendNotificationService.new(user_context: sd_context)
    count = ticket.ticket_notes.count
    retry_row = command.call(delivery: row, receipt: review[:receipt], reason: review[:reason], idempotency_key: 'r2-resend')
    expect(ticket.ticket_notes.count).to eq(count)
    expect(retry_row.attributes.values_at('original_delivery_id', 'attempt_number', 'state')).to eq([row.id, 2, 'queued'])
    expect do
      command.call(delivery: row, receipt: review[:receipt], reason: review[:reason], idempotency_key: 'r2-resend')
    end.not_to change(JrcServiceDesk::NotificationDelivery, :count)
    expect(row.reload.state).to eq('failed')
  end

  it 'never resends unknown, queued or actively dispatching attempts' do
    row = delivery
    %w[unknown queued dispatching].each do |state|
      row.update!(state: state)
      expect { JrcServiceDesk::NotificationResendPreview.new(row: row, context: context).call(reason: 'Review') }.to raise_error(ArgumentError)
    end
  end
end
