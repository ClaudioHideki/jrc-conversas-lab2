require 'rails_helper'

RSpec.describe 'Call Center queue enrollment preserves recipient corporate coverage', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:recipient) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map do |code|
      JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC #{code}")
    end
  end
  let(:units) do
    business_units.map do |business_unit|
      JrcContactCenter::Unit.create!(
        account: account, code: business_unit.code, name: business_unit.name, kind: 'sac',
        settings: { issuer_company_id: company.id, business_unit_id: business_unit.id }
      )
    end
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: units.first, code: 'A', name: 'SYNTHETIC queue') }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_memberships" }
  let(:attributes) { { queue_membership: { queue_id: queue.id, account_user_id: member.id, participates: true, supervises: false } } }

  before do
    account.enable_features!('jrc_contact_center')
    business_units
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
  end

  it 'does not transfer the administrator GROUP coverage to an eligible recipient' do
    expect { post base, headers: headers, params: attributes, as: :json }.not_to change(JrcContactCenter::QueueMembership, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('member_scope_mismatch')
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: recipient)).to be_empty
    expect(Audited.audit_class.where(auditable_type: 'JrcContactCenter::QueueMembership', associated: account)).to be_empty
  end

  it 'denies an eligible recipient covered only by another business unit' do
    JrcCrm::UserBusinessUnit.create!(
      account: account, user: recipient, scope: 'BUSINESS_UNIT', company: company, business_unit: business_units.last,
      active: true, structure_managed: true
    )
    post base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
  end

  %w[BUSINESS_UNIT COMPANY GROUP].each do |scope|
    it "permits compatible explicit #{scope} coverage without changing that coverage" do
      coverage = JrcCrm::UserBusinessUnit.create!(
        account: account, user: recipient, scope: scope, company: scope == 'GROUP' ? nil : company,
        business_unit: scope == 'BUSINESS_UNIT' ? business_units.first : nil, active: true, structure_managed: true
      )
      previous = coverage.attributes
      post base, headers: headers, params: attributes, as: :json
      expect(response).to have_http_status(:created)
      expect(JrcContactCenter::QueueMembership.find(response.parsed_body.dig('item', 'id')).account_user_id).to eq(member.id)
      expect(coverage.reload.attributes).to eq(previous)
    end
  end

  it 'permits safe deactivation after coverage revocation but rejects reactivation' do
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    patch "#{base}/#{membership.id}", headers: headers, params: { queue_membership: { active: false } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload.active).to be(false)
    patch "#{base}/#{membership.id}", headers: headers, params: { queue_membership: { active: true } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(membership.reload.active).to be(false)
  end

  it 'rejects moving an assignment to an uncovered recipient even when deactivating it' do
    actor_member = account.account_users.find_by!(user: actor)
    membership = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: actor_member)
    patch(
      "#{base}/#{membership.id}",
      headers: headers,
      params: { queue_membership: { account_user_id: member.id, active: false } },
      as: :json
    )
    expect(response).to have_http_status(:unprocessable_entity)
    expect(membership.reload).to have_attributes(account_user_id: actor_member.id, active: true)
  end

  it 'does not use supervision as a corporate coverage grant' do
    attributes[:queue_membership].merge!(participates: false, supervises: true)
    post base, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
  end
end
