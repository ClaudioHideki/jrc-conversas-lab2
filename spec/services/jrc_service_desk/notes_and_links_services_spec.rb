# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk internal notes and native conversation links' do
  include_context 'JRC Service Desk domain'
  let(:ticket) { sd_ticket }
  let(:notes) { JrcServiceDesk::AddNoteService.new(user_context: sd_context) }
  let(:links) { JrcServiceDesk::LinkConversationService.new(user_context: sd_context) }

  it 'creates an internal note once and does not duplicate the event on retry' do
    first = notes.call(ticket_id: ticket.id, attributes: { body: 'Internal note' }, idempotency_key: 'note-1')
    again = notes.call(ticket_id: ticket.id, attributes: { body: 'Internal note' }, idempotency_key: 'note-1')
    expect(again.id).to eq(first.id)
    expect(first.visibility).to eq('internal')
    expect(ticket.ticket_events.where(event_type: 'note_added').count).to eq(1)
  end

  it 'refuses different note content with the same idempotency key' do
    notes.call(ticket_id: ticket.id, attributes: { body: 'Original' }, idempotency_key: 'note-1')
    expect do
      notes.call(ticket_id: ticket.id, attributes: { body: 'Changed' }, idempotency_key: 'note-1')
    end.to raise_error(JrcServiceDesk::IdempotencyConflict)
  end

  %i[visibility author_membership_id files blob_id signed_id account_id unit_id].each do |field|
    it "does not accept #{field} through the note command" do
      expect do
        notes.call(ticket_id: ticket.id, attributes: { body: 'Test', field => 'forged' }, idempotency_key: 'note-2')
      end.to raise_error(ArgumentError)
    end
  end

  it 'rejects linking a conversation from another Account' do
    foreign = create(:conversation, account: sd_foreign_account)
    expect { links.call(ticket_id: ticket.id, conversation_id: foreign.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'requires native conversation authorization even for a visible ticket' do
    conversation = create(:conversation, account: sd_account)
    expect { links.call(ticket_id: ticket.id, conversation_id: conversation.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'links a natively accessible conversation without duplicating messages or links' do
    conversation = create(:conversation, account: sd_account)
    create(:inbox_member, user: sd_user, inbox: conversation.inbox)
    message_count = conversation.messages.count
    first = links.call(ticket_id: ticket.id, conversation_id: conversation.id)
    second = links.call(ticket_id: ticket.id, conversation_id: conversation.id)
    expect(second.id).to eq(first.id)
    expect(conversation.messages.count).to eq(message_count)
    expect(ticket.ticket_events.where(event_type: 'conversation_linked').count).to eq(1)
  end
end
