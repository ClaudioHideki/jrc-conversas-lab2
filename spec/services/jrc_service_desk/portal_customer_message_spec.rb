# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::PortalCustomerMessage do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:widget) { create(:channel_widget, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: widget.inbox) }
  let(:attributes) do
    { conversation: conversation, contact: contact, content: 'Explicit customer request', source_id: 'r2-portal-contract',
      content_attributes: { service_desk_ticket_id: '42' } }
  end

  it 'keeps the native incoming customer sender and explicit message fields' do
    message = described_class.create!(**attributes)
    expect(message).to be_incoming
    expect(message).not_to be_private
    expect(message.sender).to eq(contact)
    expect(message.conversation).to eq(conversation)
    expect(message.source_id).to eq('r2-portal-contract')
    expect(message.content_attributes['service_desk_ticket_id']).to eq('42')
  end

  it 'rejects a missing required payload field without creating a message' do
    submitted = attributes.except(:content_attributes)
    expect { described_class.create!(**submitted) }.to raise_error(ArgumentError)
    expect(conversation.messages).to be_empty
  end

  it 'rejects unknown payload fields without allowing an outgoing or private override' do
    submitted = attributes.merge(message_type: :outgoing, private: true)
    expect { described_class.create!(**submitted) }.to raise_error(ArgumentError)
    expect(conversation.messages).to be_empty
  end

  it 'rejects another contact without creating a message' do
    submitted = attributes.merge(contact: create(:contact, account: account))
    expect { described_class.create!(**submitted) }.to raise_error(Pundit::NotAuthorizedError)
    expect(conversation.messages).to be_empty
  end

  it 'rejects an email inbox instead of silently reusing the customer widget path' do
    email = create(:channel_email, account: account)
    email_conversation = create(:conversation, account: account, inbox: email.inbox, contact: contact)
    submitted = attributes.merge(conversation: email_conversation)
    expect { described_class.create!(**submitted) }.to raise_error(Pundit::NotAuthorizedError)
    expect(email_conversation.messages).to be_empty
  end
end
