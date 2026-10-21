# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CallSession do
  subject(:call_session) do
    described_class.new(account: account, correlation_id: SecureRandom.uuid, direction: 'inbound', started_at: started_at)
  end

  let(:account) { create(:account) }
  let(:started_at) { Time.current }

  it 'accepts ordered lifecycle timestamps' do
    call_session.assign_attributes(answered_at: started_at + 1.second, ended_at: started_at + 2.seconds)

    expect(call_session).to be_valid
  end

  it 'rejects answer and end timestamps before the start' do
    call_session.assign_attributes(answered_at: started_at - 1.second, ended_at: started_at - 2.seconds)

    expect(call_session).not_to be_valid
    expect(call_session.errors[:answered_at]).to include('must not be before started_at')
    expect(call_session.errors[:ended_at]).to include('must not be before started_at')
  end

  it 'rejects an end before an answer even when both follow the start' do
    call_session.assign_attributes(answered_at: started_at + 2.seconds, ended_at: started_at + 1.second)

    expect(call_session).not_to be_valid
    expect(call_session.errors[:ended_at]).to include('must not be before answered_at')
  end
end
