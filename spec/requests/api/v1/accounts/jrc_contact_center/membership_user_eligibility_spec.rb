require 'rails_helper'

RSpec.describe 'Call Center enrollment requires explicit user eligibility', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:recipient) { create(:user, account: account) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC unit', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC', name: 'SYNTHETIC queue') }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships" }

  before { account.enable_features!('jrc_contact_center') }

  it 'marks a pending native user as unavailable without treating online presence as authorization' do
    recipient.update!(availability: :online)
    get base, headers: headers
    option = response.parsed_body.fetch('agents').find { |row| row['account_user_id'] == member.id.to_s }
    expect(option).to include('eligible' => false)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: member)).to be(false)
  end

  it 'rejects a new participation assignment to a pending user' do
    attributes = { queue_membership: { queue_id: queue.id, account_user_id: member.id, participates: true, supervises: false } }
    expect { post base, headers: headers, params: attributes, as: :json }.not_to change(JrcContactCenter::QueueMembership, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('ineligible_member')
  end

  it 'rejects supervision without implicitly activating a pending user' do
    attributes = { queue_membership: { queue_id: queue.id, account_user_id: member.id, participates: false, supervises: true } }
    post base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
  end

  it 'allows an explicitly eligible user without requiring that user to be online' do
    recipient.update!(availability: :offline)
    JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: true)
    post base, headers: headers, params: { queue_membership: { queue_id: queue.id, account_user_id: member.id } }, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcContactCenter::QueueMembership.find(response.parsed_body.dig('item', 'id')).account_user_id).to eq(member.id)
  end

  it 'allows safe deactivation after eligibility has been revoked and prevents reactivation' do
    grant = JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: false)
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    patch "#{base}/#{membership.id}", headers: headers, params: { queue_membership: { active: false } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload.active).to be(false)
    patch "#{base}/#{membership.id}", headers: headers, params: { queue_membership: { active: true } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(membership.reload.active).to be(false)
    expect(grant.reload.eligible).to be(false)
  end

  it 'does not move an existing assignment to a pending user even while disabling it' do
    actor_link = account.account_users.find_by!(user: actor)
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: actor_link)
    attributes = { queue_membership: { account_user_id: member.id, active: false } }
    patch "#{base}/#{membership.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(membership.reload.account_user_id).not_to eq(member.id)
  end
end
