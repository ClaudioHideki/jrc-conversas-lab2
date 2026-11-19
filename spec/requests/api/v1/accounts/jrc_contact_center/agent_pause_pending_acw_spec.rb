require 'rails_helper'

RSpec.describe 'Native operator pause while ACW is pending', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago)
  end
  let!(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, direction: 'inbound',
                                      status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state" }

  before { account.enable_features!('jrc_contact_center') }

  it 'rejects a direct authenticated pause request without altering the pending qualification or state' do
    call.update!(status: 'ended', ended_at: Time.current)
    record = JrcContactCenter::Qualification.pending.find_by!(call_session: call, account_user: member)
    record.update!(notes: 'SYNTHETIC private draft')
    state = JrcContactCenter::AgentStateSnapshot.new(account_user: member)
    before = member.reload.availability
    payload = { state: 'paused', reason_code: 'lunch', command_id: SecureRandom.uuid, expected_state_version: state.version }
    patch endpoint, headers: headers, params: { agent_state: payload }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('tabulation_pending')
    expect(record.reload).to have_attributes(completed_at: nil, notes: 'SYNTHETIC private draft')
    expect(leg.reload).to have_attributes(account_user_id: member.id, call_session_id: call.id)
    expect(member.reload.availability).to eq(before)
    expect(response.body).not_to include('SYNTHETIC private draft')
    expect(JrcContactCenter::AgentStateEvent.where(account_user: member, state: 'paused')).to be_empty
  end
end
