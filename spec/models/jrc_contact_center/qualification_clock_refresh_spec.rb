require 'rails_helper'

RSpec.describe 'Native qualification clock refresh against a stale persisted row', type: :model do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account, name: 'SYNTHETIC clock account') }
  let(:operator) do
    create(:user, :contact_center_eligible, account: account, name: 'SYNTHETIC clock operator', display_name: 'SYNTHETIC clock operator',
                                          email: "synthetic-clock-#{SecureRandom.uuid}@example.test")
  end
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'ended', started_at: 10.minutes.ago,
                                          answered_at: 9.minutes.ago, ended_at: 5.minutes.ago)
  end
  let(:record) do
    JrcContactCenter::Qualification.create!(account: account, account_user: member, call_session: call,
                                            channel: 'voice', started_at: call.ended_at, acw_limit_seconds: 180)
  end

  around { |example| freeze_time { example.run } }

  it 'refreshes the derived clock on the current pending row without completing or restarting attendance' do
    original_start = record.started_at
    refreshed = record.refresh_overdue!
    expect(refreshed).to equal(record)
    expect(record.reload).to have_attributes(overdue: true, exceeded_seconds: 120, completed_at: nil, duration_seconds: nil)
    expect(record.started_at).to eq(original_start)
    expect(record.reason_code).to be_nil
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'cannot overwrite a completed result through an AR copy read while it was still pending' do
    stale = JrcContactCenter::Qualification.find(record.id)
    record.update!(completed_at: Time.current, duration_seconds: 100, reason_code: 'resolved', outcome_code: 'completed',
                   overdue: false, exceeded_seconds: 0, notes: 'SYNTHETIC immutable completion result')
    completed = record.attributes
    travel 20.seconds
    payload = stale.operational_payload
    expect(record.reload.attributes).to eq(completed)
    expect(stale.attributes).to eq(completed)
    expect(stale.completed_at).to be_present
    expect(payload).to include('completed_at' => record.completed_at.as_json, 'overdue' => false, 'elapsed_seconds' => 100)
  end

  it 'cannot restore an obsolete exceeded duration after the current pending limit increases' do
    stale = JrcContactCenter::Qualification.find(record.id)
    record.update!(reason_code: 'order', acw_limit_seconds: 600, overdue: false, exceeded_seconds: 0)
    updated = record.attributes
    travel 20.seconds
    payload = stale.operational_payload
    expect(record.reload.attributes).to eq(updated)
    expect(stale).to have_attributes(acw_limit_seconds: 600, overdue: false, exceeded_seconds: 0, completed_at: nil)
    expect(stale.started_at).to eq(updated.fetch('started_at'))
    expect(payload).to include('acw_limit_seconds' => 600, 'reason_code' => 'order', 'overdue' => false)
  end

  it 'keeps a not-yet-overdue row unchanged during an ordinary clock read' do
    record.update!(acw_limit_seconds: 600)
    original = record.attributes
    expect(record.refresh_overdue!).to equal(record)
    expect(record.reload.attributes).to eq(original)
  end

  it 'does not expose or change a row whose native account membership owner changed after the original read' do
    stale = JrcContactCenter::Qualification.find(record.id)
    another = create(:user, :contact_center_eligible, account: account)
    other_member = account.account_users.find_by!(user: another)
    record.update!(account_user: other_member, notes: 'SYNTHETIC other operator private draft')
    updated = record.attributes
    expect { stale.operational_payload }.to raise_error(ActiveRecord::RecordNotFound)
    expect(record.reload.attributes).to eq(updated)
  end

  it 'keeps a completed row unchanged during an ordinary historical read' do
    record.update!(completed_at: Time.current, duration_seconds: 300, reason_code: 'resolved', outcome_code: 'completed',
                   overdue: true, exceeded_seconds: 120)
    original = record.attributes
    travel 20.seconds
    expect(record.refresh_overdue!).to equal(record)
    expect(record.reload.attributes).to eq(original)
  end

  it 'refreshes repeated pending reads from the actual row while preserving native identifiers and notes' do
    record.update!(notes: 'SYNTHETIC pending note')
    original = record.attributes.except('overdue', 'exceeded_seconds', 'updated_at')
    record.refresh_overdue!
    travel 20.seconds
    record.refresh_overdue!
    expect(record.reload).to have_attributes(overdue: true, exceeded_seconds: 140)
    expect(record.attributes.except('overdue', 'exceeded_seconds', 'updated_at')).to eq(original)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end
