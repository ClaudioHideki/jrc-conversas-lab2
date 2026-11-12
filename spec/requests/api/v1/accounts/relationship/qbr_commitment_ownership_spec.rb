require 'rails_helper'

RSpec.describe 'Relationship QBR commitment ownership', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/records/qbrs" }
  let(:fields) do
    { assignment_id: assignment.id, title: 'Synthetic QBR', scheduled_at: 1.day.from_now.iso8601,
      request_id: SecureRandom.uuid, status: 'completed', summary: 'Synthetic reviewed customer decisions',
      decisions: [{ decision_key: 'followup', title: 'Synthetic commitment', due_at: 2.days.from_now.iso8601, owner_id: target.id }] }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def counts
    [JrcRelationship::Qbr, JrcRelationship::Action, JrcCrm::Activity, JrcCrm::AuditEvent].map { |model| model.where(account: account).count }
  end

  it 'refuses a new completed QBR with an inactive commitment target atomically' do
    target.update!(confirmed_at: nil)
    before = counts
    post url, headers: headers, params: { record: fields }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(counts).to eq(before)
  end

  it 'refuses a scheduled commitment outside the target native portfolio scope' do
    target.account_users.find_by!(account: account).update!(role: :agent)
    before = counts
    post url, headers: headers, params: { record: fields.merge(status: 'scheduled') }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(counts).to eq(before)
  end

  it 'keeps valid offline commitment ownership and native Agenda projection idempotent' do
    target.account_users.find_by!(account: account).update!(availability: :offline)
    post url, headers: headers, params: { record: fields }, as: :json
    expect(response).to have_http_status(:created)
    qbr = JrcRelationship::Qbr.find(response.parsed_body.fetch('id'))
    before = counts
    patch "#{url}/#{qbr.id}", headers: headers, params: { record: fields.merge(lock_version: qbr.lock_version) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(counts.take(3)).to eq(before.take(3))
    activity = JrcCrm::Activity.find_by!(account: account, title: 'Synthetic commitment')
    expect(activity.user_id).to eq(target.id)
    expect(assignment.actions.find_by!(activity_id: activity.id).owner_id).to eq(target.id)
  end

  it 'preserves unchanged historical commitment ownership when its user later becomes inactive' do
    post url, headers: headers, params: { record: fields }, as: :json
    expect(response).to have_http_status(:created)
    qbr = JrcRelationship::Qbr.find(response.parsed_body.fetch('id'))
    target.update!(confirmed_at: nil)
    patch "#{url}/#{qbr.id}", headers: headers, params: { record: fields.merge(lock_version: qbr.lock_version, title: 'Synthetic revised title') },
                              as: :json
    expect(response).to have_http_status(:ok)
    expect(qbr.reload.decisions.first.fetch('owner_id')).to eq(target.id)
    expect(JrcCrm::Activity.find_by!(account: account, title: 'Synthetic commitment').user_id).to eq(target.id)
  end
end
