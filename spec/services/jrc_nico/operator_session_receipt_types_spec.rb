require 'rails_helper'

RSpec.describe JrcNico::OperatorSession do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:operator) { described_class.new(account: account, user: actor) }
  let(:access) { operator.access }

  it 'does not treat an unsupported saved native resource as authorized and preserves succeeded audit while cancelling pending work' do
    session = operator.session
    session.append('assistant', 'Synthetic summary from an unsupported source')
    session.update!(context: session.context.merge('resources' => [['Unregistered::PrivateReceipt', account.id]]))
    pending = session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic pending review', status: 'awaiting_confirmation')
    completed = session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic completed audit', status: 'succeeded')
    original = completed.attributes.deep_dup
    current = described_class.new(account: account, user: actor)
    expect(current.session.reload.messages).to eq([])
    expect(current.session.context).not_to have_key('resources')
    expect(pending.reload.status).to eq('cancelled')
    expect(completed.reload.attributes).to eq(original)
  end

  it 'retains known authorized Contact history and pending work rather than clearing a valid legacy source receipt' do
    contact = create(:contact, account: account)
    session = operator.session
    session.append('assistant', 'Synthetic authorized contact summary')
    session.update!(context: session.context.merge('resources' => [['Contact', contact.id]]))
    pending = session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic valid pending review', status: 'awaiting_confirmation')
    current = described_class.new(account: account, user: actor)
    expect(current.session.reload.messages.last.fetch('content')).to eq('Synthetic authorized contact summary')
    expect(current.session.context.fetch('resources')).to eq([['Contact', contact.id]])
    expect(pending.reload.status).to eq('awaiting_confirmation')
  end

  it 'preserves legacy plain conversation history without manufacturing a native source receipt' do
    operator.session.append('user', 'Synthetic plain operator note')
    current = described_class.new(account: account, user: actor)
    expect(current.session.messages.last.fetch('content')).to eq('Synthetic plain operator note')
  end

  it 'recognizes the existing Inbox receipt through its native current policy and account boundary' do
    inbox = create(:inbox, account: account)
    foreign = create(:inbox)
    previous = [Current.account, Current.user, Current.account_user]
    expect(JrcNico::DomainAccess.authorize_resource!(access, 'Inbox', inbox.id)).to eq(inbox)
    expect([Current.account, Current.user, Current.account_user]).to eq(previous)
    expect do
      JrcNico::DomainAccess.authorize_resource!(access, 'Inbox', foreign.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    session = operator.session
    session.append('assistant', 'Synthetic native inbox summary')
    session.update!(context: session.context.merge('resources' => [['Inbox', inbox.id]]))
    expect(described_class.new(account: account, user: actor).session.messages.last.fetch('content')).to eq('Synthetic native inbox summary')
  end

  it 'does not authorize an unassigned Inbox merely because the operator belongs to the Account' do
    inbox = create(:inbox, account: account)
    agent = create(:user, account: account, role: :agent)
    current = JrcNico::OperationalAccess.new(account: account, user: agent)
    expect do
      JrcNico::DomainAccess.authorize_resource!(current, 'Inbox', inbox.id)
    end.to raise_error(Pundit::NotAuthorizedError)
  end
end
