# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CommandDispatcher do
  let(:account) { create(:account) }

  it 'tracks unavailable provider commands without calling an external endpoint' do
    agent = create(:user, account: account, role: :agent)
    member = account.account_users.find_by!(user: agent)

    expect do
      described_class.new(account: account, actor_account_user: member).call(action: 'originate', parameters: {})
    end.to raise_error(JrcContactCenter::Providers::BaseAdapter::CapabilityUnavailable)
    expect(JrcContactCenter::Command.where(account: account).sole).to have_attributes(status: 'unknown', action: 'originate')
  end

  it 'preserves all existing optional command keywords' do
    agent = create(:user, account: account, role: :agent)
    member = account.account_users.find_by!(user: agent)
    session = JrcContactCenter::CallSession.create!(account: account, correlation_id: SecureRandom.uuid, direction: 'inbound',
                                                    started_at: Time.current)
    adapter = instance_double(JrcContactCenter::Providers::BaseAdapter)
    allow(adapter).to receive(:dispatch).and_return({ accepted: true })
    command_id = SecureRandom.uuid

    command = described_class.new(account: account, actor_account_user: member, adapter: adapter).call(
      action: 'hold', parameters: { requested: true }, call_session: session,
      reason_code: 'test', expected_state_version: 3, command_id: command_id
    )

    expect(command).to have_attributes(status: 'accepted_by_gateway', call_session: session, command_id: command_id,
                                       reason_code: 'test', expected_state_version: 3, parameters: { 'requested' => true })
  end
end
