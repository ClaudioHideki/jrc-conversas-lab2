require 'rails_helper'

RSpec.describe 'Call Center queue enrollment eligibility', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC queue') }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships" }

  before { account.enable_features!('jrc_contact_center') }

  it 'rejects a new link to an inactive queue without persisting a partial enrollment' do
    queue.update!(status: 'inactive')
    expect do
      post base, headers: headers, as: :json, params: { queue_membership: { queue_id: queue.id, account_user_id: member.id } }
    end.not_to change(JrcContactCenter::QueueMembership, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('inactive_queue')
  end

  it 'rejects reactivation on an inactive queue and preserves the existing inactive link' do
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, active: false)
    queue.update!(status: 'inactive')
    patch "#{base}/#{membership.id}", headers: headers, as: :json, params: { queue_membership: { active: true } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(membership.reload.active).to be(false)
  end

  it 'permits deactivation of an existing link after the queue was inactivated' do
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, active: true)
    queue.update!(status: 'inactive')
    patch "#{base}/#{membership.id}", headers: headers, as: :json, params: { queue_membership: { active: false } }
    expect(response).to have_http_status(:success)
    expect(membership.reload.active).to be(false)
  end

  it 'rejects moving an existing link into an inactive queue without overwriting its origin' do
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    inactive = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'INACTIVE', name: 'SYNTHETIC inactive', status: 'inactive')
    patch "#{base}/#{membership.id}", headers: headers, as: :json, params: { queue_membership: { queue_id: inactive.id } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(membership.reload.queue_id).to eq(queue.id)
  end
end
