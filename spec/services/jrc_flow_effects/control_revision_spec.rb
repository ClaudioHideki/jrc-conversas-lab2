require 'rails_helper'

RSpec.describe JrcFlowEffects::ControlRevision do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:user) { create(:user, account: account) }

  def revision
    conversation.reload.attributes.fetch('jrc_effect_control_revision', 0)
  end

  it 'changes atomically for assignment through update_column' do
    operator = user
    expect { conversation.update_column(:assignee_id, operator.id) }.to change { revision }.by(1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
  end

  it 'changes for team and status through update_all' do
    team = create(:team, account: account)
    expect { Conversation.where(id: conversation.id).update_all(team_id: team.id, status: 1) }.to change { revision }.by(1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
  end

  [false, true].each do |private_message|
    it "changes in the transaction creating an outgoing User message, private=#{private_message}" do
      operator = user
      conversation
      previous = revision
      Message.transaction do
        Messages::MessageBuilder.new(operator, conversation, content: 'Human', private: private_message,
                                                             content_attributes: { jrc_flow_effect_id: SecureRandom.uuid,
                                                                                   jrc_flow_effect_organization_id: SecureRandom.uuid }).perform
        expect(revision).to eq(previous + 1)
        raise ActiveRecord::Rollback
      end
      expect(revision).to eq(previous)
    end
  end

  it 'changes for NICO human message metadata without exemptions' do
    operator = user
    expect do
      Messages::MessageBuilder.new(operator, conversation, content: 'NICO', private: false,
                                                           content_attributes: { jrc_nico_takeover: { takeoverId: SecureRandom.uuid } }).perform
    end.to change { revision }.by(1)
  end

  it 'counts a native human external echo as control even without a User sender' do
    expect do
      create(:message, conversation: conversation, account: account, inbox: conversation.inbox,
                       message_type: :outgoing, sender: conversation.contact, content_attributes: { 'external_echo' => true })
    end.to change { revision }.by(1)
  end

  it 'recognizes direct SQL JSON-object echoes as well as the Rails JSON-string representation' do
    conversation
    expect do
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        INSERT INTO messages(account_id, inbox_id, conversation_id, message_type, content_type, content_attributes, created_at, updated_at)
        VALUES(#{account.id}, #{conversation.inbox_id}, #{conversation.id}, 1, 0, '{"external_echo":true}'::json, now(), now())
      SQL
    end.to change { revision }.by(1)
  end

  it 'changes for NICO control and custom attribute updates' do
    expect do
      conversation.update_column(:custom_attributes, { 'nico_control' => 'paused', 'human_key' => false }) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
    end.to change { revision }.by(1)
  end

  it 'changes for routing changes even when callbacks are bypassed' do
    conversation
    expect { conversation.contact_inbox.update_column(:source_id, SecureRandom.uuid) }.to change { revision }.by(1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
    expect { conversation.update_column(:contact_id, create(:contact, account: account).id) }.to change { revision }.by(1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
  end

  it 'changes for Contact delivery identity updates without callbacks' do
    conversation
    expect { conversation.contact.update_column(:email, 'new-route@example.test') }.to change { revision }.by(1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
  end

  it 'changes when the same Inbox points to another channel without callbacks' do
    conversation
    channel = create(:channel_widget, account: account)
    expect { conversation.inbox.update_column(:channel_id, channel.id) }.to change { revision }.by(1) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
  end

  it 'changes through the existing NICO private-send path' do
    account.update!(custom_attributes: { 'nico_enabled' => true })
    operator = create(:user, account: account, role: :administrator)
    access = JrcNico::OperationalAccess.new(account: account, user: operator)
    expect do
      JrcNico::ToolExecutor.new(access).call('send_message',
                                             'conversation_id' => conversation.display_id, 'content' => 'NICO private note', 'private' => true)
    end.to change { revision }.by(1)
  end

  it 'does not change for read markers or incoming messages' do
    expect { conversation.update_column(:agent_last_seen_at, Time.current) }.not_to(change { revision }) # rubocop:disable Rails/SkipsModelValidations -- Prove SQL paths bypassing callbacks retain the guard.
    expect { create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming) }
      .not_to(change { revision })
  end

  it 'changes for label edits and rolls back with them' do
    conversation
    previous = revision
    Conversation.transaction do
      conversation.update!(label_list: ['human-label'])
      expect(revision).to be > previous
      raise ActiveRecord::Rollback
    end
    expect(revision).to eq(previous)
  end
end
