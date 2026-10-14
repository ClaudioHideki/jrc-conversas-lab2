require 'rails_helper'
RSpec.describe JrcOperator::Commands do
  let(:account) { create(:account) }
  let(:company) { JrcCustomers::Company.create!(account: account, name: 'Synthetic issuer', relationship_type: 'internal') }
  let(:unit) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'Synthetic unit', code: 'SYNTHETIC') }
  let(:contact) { create(:contact, account: account) }
  let(:user) { create(:user, account: account) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:role) { create(:custom_role, account: account, permissions: JrcOperator::Access::PERMISSIONS + ['conversation_manage']) }
  let(:binding) do
    JrcOperator::Binding.create!(account: account, company: company, business_unit: unit, contact: contact, bemtevi_customer_id: '777', active: true)
  end
  let(:access) { JrcOperator::Access.new(account: account, user: user) }
  let(:client) { instance_double(JrcOperator::Client) }
  let(:commands) { described_class.new(binding: binding, user: user) }
  let(:key) { 'synthetic-idempotency-00001' }

  before do
    account.enable_features!('jrc_operator')
    member.update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: user, company: company, business_unit: unit, scope: 'BUSINESS_UNIT',
                                     structure_managed: true, active: true)
  end

  it('defaults OFF for new accounts') { expect(create(:account).feature_enabled?('jrc_operator')).to be(false) }
  it('resolves only authorized active bindings') { expect(access.binding!(binding.id)).to eq(binding) }

  it 'denies a configured binding after disabling the module' do
    binding
    account.disable_features!('jrc_operator')
    expect { access.binding!(binding.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not grant new capabilities to an administrator automatically' do
    binding
    member.update!(role: :administrator, custom_role: nil)
    expect { access.binding!(binding.id) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'denies legacy users without organizational membership' do
    binding
    JrcCrm::UserBusinessUnit.where(user: user).delete_all
    expect { access.binding!(binding.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'denies inactive units and foreign accounts' do
    binding
    unit.update!(active: false)
    expect { access.binding!(binding.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcOperator::Binding.new(account: create(:account), company: company, business_unit: unit, contact: contact,
                                    bemtevi_customer_id: '777')).not_to be_valid
  end

  it 'validates an incomplete operation as invalid rather than raising or persisting it' do
    operation = JrcOperator::Operation.new(user: user, conversation: create(:conversation, account: account),
                                           key: key, kind: 'send_boleto')
    expect(operation).not_to be_valid
    expect(operation.errors[:conversation]).to include('must match customer')
    expect(operation).to be_new_record
  end

  context 'when executing persistent commands' do
    before { allow(JrcOperator::Client).to receive(:new).with(binding).and_return(client) }

    it 'reserves once and returns the same persisted operation on retry' do
      allow(client).to receive(:rede).with(:reserve, { 'number_id' => 'synthetic', 'external_actor' => user.id.to_s },
                                           key: key).and_return({ 'reservation_id' => 'synthetic-reservation', 'status' => 'ativa' })
      first = commands.remote!('reserve', { 'number_id' => 'synthetic' }, key)
      second = commands.remote!('reserve', { 'number_id' => 'synthetic' }, key)
      expect(second.id).to eq(first.id)
      expect(client).to have_received(:rede).once
    end

    it 'reconciles a timeout without repeating the reservation POST' do
      allow(client).to receive(:rede).with(:reserve, anything, key: key).and_raise(JrcOperator::Error.new('REMOTE_UNAVAILABLE', 503))
      expect { commands.remote!('reserve', { 'number_id' => 'synthetic' }, key) }.to raise_error(JrcOperator::Error)
      expect(binding.operations.first.state).to eq('pending')
      allow(client).to receive(:rede).with(:operation,
                                           { 'key' => key,
                                             'external_actor' => user.id.to_s }).and_return({ 'reservation_id' => 'confirmed-remotely' })
      expect(commands.remote!('reserve', { 'number_id' => 'synthetic' }, key).state).to eq('confirmed')
      expect(client).to have_received(:rede).with(:reserve, anything, key: key).once
    end

    it 'rejects reuse of a key with a different request or revoked grant' do
      allow(client).to receive(:rede).and_return({ 'reservation_id' => 'synthetic' })
      commands.remote!('reserve', { 'number_id' => 'one' }, key)
      expect { commands.remote!('reserve', { 'number_id' => 'two' }, key) }.to raise_error(JrcOperator::Error, 'IDEMPOTENCY_CONFLICT')
      role.update!(permissions: ['jrc_operator_read'])
      expect { commands.remote!('reserve', { 'number_id' => 'one' }, key) }.to raise_error(Pundit::NotAuthorizedError)
    end

    it 'retrieves a PDF without creating messages, invoices or payments' do
      allow(client).to receive(:collectible!).with('44').and_return({ 'id' => '44' })
      allow(client).to receive(:bemtevi).with('cobranca/segundaVia', { 'codcobranca' => 44 }, pdf: true).and_return("%PDF-1.4\nSynthetic document")
      expect { commands.prepare!('44', key) }.not_to change(Message, :count)
      expect(binding.operations.first.boleto).to be_attached
      expect(JrcCrm::Invoice.count).to eq(0)
      expect(JrcCrm::Payment.count).to eq(0)
    end

    it 'schedules a PDF once even when a second HTTP key is supplied' do
      allow(client).to receive(:collectible!).and_return({ 'id' => '44' })
      allow(client).to receive(:bemtevi).and_return("%PDF-1.4\nSynthetic document")
      prepared = commands.prepare!('44', key)
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: user)
      binding.update!(allowed_inbox_ids: [inbox.id])
      conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
      message = create(:message, conversation: conversation, account: account)
      builder = instance_double(Messages::MessageBuilder, perform: message)
      allow(Messages::MessageBuilder).to receive(:new).and_return(builder)
      first = commands.send!(prepared.id, conversation.id, 'Synthetic boleto message', 'synthetic-send-key-0001')
      second = commands.send!(prepared.id, conversation.id, 'Synthetic boleto message', 'synthetic-send-key-0002')
      expect(second.id).to eq(first.id)
      expect(builder).to have_received(:perform).once
    end

    it 'denies a different customer and a paid title at delivery time' do
      allow(client).to receive(:collectible!).and_return({ 'id' => '44' })
      allow(client).to receive(:bemtevi).and_return("%PDF-1.4\nSynthetic document")
      prepared = commands.prepare!('44', key)
      other = create(:conversation, account: account)
      expect { commands.send!(prepared.id, other.id, 'message', 'synthetic-send-key-0001') }.to raise_error(Pundit::NotAuthorizedError)
      inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: inbox, user: user)
      binding.update!(allowed_inbox_ids: [inbox.id])
      conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
      allow(client).to receive(:collectible!).and_raise(JrcOperator::Error, 'CHARGE_NOT_COLLECTIBLE')
      expect do
        commands.send!(prepared.id, conversation.id, 'message', 'synthetic-send-key-0001')
      end.to raise_error(JrcOperator::Error, 'CHARGE_NOT_COLLECTIBLE')
      expect(Messages::MessageBuilder).not_to receive(:new)
    end
  end
end
