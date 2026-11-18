require 'rails_helper'

RSpec.describe JrcContactCenter::CallObservationWriter do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: Time.current,
                                          metadata: { 'retained' => 'SYNTHETIC' })
  end

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at)
  end

  it 'persists only a note and treats an unchanged current-version retry as the same revision' do
    described_class.call(call: call, text: 'SYNTHETIC note', version: call.lock_version, member: member)
    expect(call.reload.metadata.fetch('retained')).to eq('SYNTHETIC')
    expect(call.metadata.dig('attendance_observations', 'account_user_id')).to eq(member.id)
    expect do
      described_class.call(call: call, text: 'SYNTHETIC note', version: call.lock_version, member: member)
    end.not_to change(JrcContactCenter::CallObservation, :count)
    expect(call.reload.status).to eq('connected')
    expect(call.legs.pluck(:account_user_id)).to eq([member.id])
    expect(JrcContactCenter::Qualification.where(call_session: call)).to be_empty
  end

  it 'does not use the previously loaded native role after a restrictive custom role is assigned' do
    member.custom_role
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    account.account_users.find(member.id).update!(custom_role: role)
    expect do
      described_class.call(call: call, text: 'Denied', version: call.lock_version, member: member)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(call.reload.metadata).not_to have_key('attendance_observations')
    expect(JrcContactCenter::CallObservation.where(call_session: call)).to be_empty
  end

  it 'rejects explicitly revoked eligibility even through a direct service invocation' do
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    expect do
      described_class.call(call: call, text: 'Denied', version: call.lock_version, member: member)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(call.reload.metadata).not_to have_key('attendance_observations')
  end

  it 'rechecks the current assignment instead of reusing a previously authorized call object' do
    call.legs.destroy_all
    expect do
      described_class.call(call: call, text: 'Denied', version: call.lock_version, member: member)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(call.reload.metadata).not_to have_key('attendance_observations')
  end

  it 'does not accept a member of another account' do
    outsider = create(:user, :contact_center_eligible, account: create(:account), role: :administrator)
    foreign = outsider.account_users.first
    expect do
      described_class.call(call: call, text: 'Denied', version: call.lock_version, member: foreign)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::CallObservation.where(call_session: call)).to be_empty
  end

  it 'rolls the current note back if the native revision validation rejects persistence' do
    original = call.attributes
    expect do
      described_class.call(call: call, text: 'x' * 1001, version: call.lock_version, member: member)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(call.reload.attributes).to eq(original)
    expect(JrcContactCenter::CallObservation.where(call_session: call)).to be_empty
  end
end
