# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CallObservationWriter do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                        direction: 'inbound', status: 'connected', started_at: Time.current)
  end

  it 'rolls back the latest note when storing its revision fails' do
    allow(JrcContactCenter::CallObservation).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'synthetic failure')
    original_version = call.lock_version
    expect do
      described_class.call(call: call, text: 'Sintético', version: original_version, member: member)
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(call.reload.metadata).not_to have_key('attendance_observations')
    expect(call.lock_version).to eq(original_version)
  end

  it 'does not allow application code to overwrite or remove a saved revision' do
    described_class.call(call: call, text: 'Sintético', version: call.lock_version, member: member)
    revision = JrcContactCenter::CallObservation.find_by!(call_session: call)
    expect { revision.update!(text: 'Outra') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { revision.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
