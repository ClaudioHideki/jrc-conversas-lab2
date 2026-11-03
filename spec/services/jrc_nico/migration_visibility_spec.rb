require 'rails_helper'

RSpec.describe 'NICO migration acceptance boundaries' do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Pending imported customer') }
  let(:native) { create(:contact, account: account, name: 'Native customer') }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:access) { JrcNico::OperationalAccess.new(account: account, user: admin).authorize! }
  let(:batch) do
    JrcMigrations::Batch.create!(account: account, created_by: admin, source: 'nico_fixture', domain: 'contacts', source_digest: 'a' * 64)
  end
  let!(:mapping) do
    JrcMigrations::Mapping.create!(account: account, batch: batch, source: 'nico_fixture', domain: 'contacts', legacy_id: 'one',
      target_id: contact.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
  end

  it 'filters list, search and count while preserving native human-visible rows' do
    native
    executor = JrcNico::ToolExecutor.new(access)
    expect(executor.call('list_contacts', {}).map { |row| row['id'] }).to eq([native.id])
    expect(executor.call('search_contacts', { 'query' => 'Pending' })).to eq([])
    expect(executor.call('count_contacts', {})).to eq(count: 1)
    expect(account.contacts.find(contact.id)).to eq(contact)
  end

  it 'denies direct contacts and conversations until acceptance and rechecks revocation' do
    expect { access.contact(contact.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { access.conversation(conversation.display_id) }.to raise_error(ActiveRecord::RecordNotFound)
    mapping.update!(accepted_at: Time.current, accepted_by: admin)
    expect(access.contact(contact.id)).to eq(contact)
    expect(access.conversation(conversation.display_id)).to eq(conversation)
    mapping.update!(accepted_at: nil, accepted_by: nil)
    expect { access.contact(contact.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'blocks analysis before public conversation text reaches the context' do
    create(:message, account: account, conversation: conversation, content: 'Imported private-to-NICO fact', private: false)
    expect do
      JrcNico::ContextBuilder.new(account: account, user: admin, conversation: conversation).build('resumo')
    end.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'revalidates a selected conversation and a direct projection retained before revocation' do
    mapping.update!(accepted_at: Time.current, accepted_by: admin)
    selected = access.conversation(conversation.display_id)
    context = JrcNico::OperatorContext.new(access: access, session: nil, selected: selected)
    projection = JrcNico::ToolResultProjection.new(access, account: account)
    mapping.update!(accepted_at: nil, accepted_by: nil)
    expect { context.selected_conversation }.to raise_error(ActiveRecord::RecordNotFound)
    expect { projection.contact_snapshot(contact) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { projection.conversation_snapshot(selected) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'changes the history boundary on acceptance and delta without touching native policies' do
    pending = JrcNico::OperatorContext.access_digest(access)
    mapping.update!(accepted_at: Time.current, accepted_by: admin)
    accepted = JrcNico::OperatorContext.access_digest(access)
    expect(accepted).not_to eq(pending)
    mapping.update!(accepted_at: nil, accepted_by: nil)
    expect(JrcNico::OperatorContext.access_digest(access)).to eq(pending)
    expect(access.policy(contact).show?).to be(true)
  end

  it 'keeps another tenant mapping from blocking the native contact' do
    mapping.destroy!
    foreign = create(:account)
    foreign_admin = create(:user, account: foreign, role: :administrator)
    foreign_batch = JrcMigrations::Batch.create!(account: foreign, created_by: foreign_admin, source: 'other', domain: 'contacts', source_digest: 'a' * 64)
    JrcMigrations::Mapping.create!(account: foreign, batch: foreign_batch, source: 'other', domain: 'contacts', legacy_id: 'one',
      target_id: contact.id, source_digest: 'a' * 64, target_digest: 'b' * 64, source_updated_at: Time.current)
    expect(access.contact(contact.id)).to eq(contact)
  end
end
