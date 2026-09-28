# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk feature and identity gates for commands' do
  include_context 'JRC Service Desk domain'

  it 'denies all introduced commands with the flag disabled' do
    ticket = sd_ticket
    attrs = sd_create_attributes
    sd_account.disable_features!('jrc_service_desk')
    commands = [
      -> { JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id, attributes: attrs, idempotency_key: 'disabled') },
      -> { JrcServiceDesk::FindTicketService.new(user_context: sd_context).call(ticket_id: ticket.id) },
      -> { JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: { title: 'X' }, expected_lock_version: 0) },
      -> { JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: { assignee_account_user_id: nil }, expected_lock_version: 0) },
      -> { JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: { body: 'X' }, idempotency_key: 'disabled') },
      -> { JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: ticket.id, conversation_id: 1) },
      -> { JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: sd_snapshot_attributes) }
    ]
    commands.each { |command| expect(&command).to raise_error(Pundit::NotAuthorizedError) }
    expect(ticket.reload.title).to eq('Test ticket')
    expect(ticket.ticket_events).to be_empty
  end

  it 'denies record reads after membership revocation' do
    ticket = sd_ticket
    sd_membership.update!(active: false)
    expect { JrcServiceDesk::FindTicketService.new(user_context: sd_context).call(ticket_id: ticket.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'denies a manipulated Account/AccountUser identity pair' do
    foreign = create(:account_user, account: sd_foreign_account, user: sd_user)
    context = sd_context.merge(account_user: foreign)
    expect { JrcServiceDesk::FindTicketService.new(user_context: context).call(ticket_id: sd_ticket.id) }.to raise_error(Pundit::NotAuthorizedError)
  end
end
