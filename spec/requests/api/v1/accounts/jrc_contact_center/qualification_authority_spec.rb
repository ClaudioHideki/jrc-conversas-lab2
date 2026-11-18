require 'rails_helper'

RSpec.describe 'Call Center native qualification origin authority', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC ACW origin', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map { |code| JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC ACW #{code}") }
  end
  let(:units) do
    business_units.map do |business|
      JrcContactCenter::Unit.create!(account: account, name: business.name, code: business.code, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end
  let(:queues) do
    units.map { |unit| JrcContactCenter::Queue.create!(account: account, unit: unit, name: unit.name, code: unit.code) }
  end
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                         direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago,
                                         current_unit_id: units.first.id, current_queue_id: queues.first.id)
  end
  let!(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, queue: queues.first,
                                     direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
  end
  let(:record) do
    call.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: call)
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}" }
  let(:attributes) { { qualification: { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC origin completion' } } }

  before do
    account.enable_features!('jrc_contact_center')
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: business_units.first, active: true, structure_managed: true)
  end

  it 'completes owned attendance through the API when a transfer remains inside its authorized unit' do
    record
    sibling = JrcContactCenter::Queue.create!(account: account, unit: units.first, name: 'SYNTHETIC sibling', code: 'SIBLING')
    call.update!(current_queue_id: sibling.id)
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload).to have_attributes(reason_code: 'order', outcome_code: 'completed')
    expect(record.completed_at).to be_present
    expect(record.notes).to eq('SYNTHETIC origin completion')
  end

  it 'denies completion of a formerly visible call that is now outside the authorized business unit' do
    record
    call.update!(current_unit_id: units.last.id, current_queue_id: queues.last.id)
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:not_found)
    expect(record.reload).to have_attributes(completed_at: nil, reason_code: nil, notes: nil)
    expect(JrcContactCenter::AgentStateEvent.find_by!(account: account, external_event_id: "qualification:#{record.id}:pending").ended_at).to be_nil
  end

  it 'does not use a caller supplied account or user ID to expand completion authority' do
    record
    outsider = create(:user, :contact_center_eligible, account: create(:account), role: :administrator)
    data = attributes.merge(account_id: account.id, account_user_id: member.id, user_id: actor.id)
    patch endpoint, headers: outsider.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.completed_at).to be_nil
  end
end
