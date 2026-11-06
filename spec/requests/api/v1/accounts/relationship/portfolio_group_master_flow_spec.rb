require 'rails_helper'

RSpec.describe 'Master customer to operational portfolio flow', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'Synthetic existing master customer', relationship_type: 'customer') }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic master flow portfolio') }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists one native allocation then explicitly reviews links into multiple active groups without duplicating customers or ownership' do
    company
    before = account.master_companies.count
    get "#{base}/portfolio", headers: headers, params: { company_id: company.id, page: 1, per_page: 1 }
    expect(response.parsed_body.fetch('payload')).to eq([])
    post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { company_id: company.id, owner_id: actor.id } }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    get "#{base}/portfolio", headers: headers, params: { company_id: company.id, page: 1, per_page: 1 }
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([id])
    other = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic other active portfolio')
    [group, other].each do |portfolio|
      patch "#{base}/portfolio_groups/#{portfolio.id}/customers", headers: headers, as: :json, params: {
        assignment_ids: [id], active: true, expected_version: 0, reason: 'Reviewed existing master customer link'
      }
      expect(response).to have_http_status(:ok)
      get "#{base}/portfolio_groups/#{portfolio.id}/customers", headers: headers
      expect(response.parsed_body.fetch('payload').pluck('id')).to eq([id])
    end
    expect([account.master_companies.count, JrcRelationship::Assignment.where(account: account).count]).to eq([before, 1])
    expect([JrcRelationship::Assignment.find(id).owner_id,
            JrcRelationship::PortfolioGroupAssignment.where(account: account, assignment_id: id, active: true).count]).to eq([actor.id, 2])
  end

  it 'preserves a pre-existing allocation and its responsibilities on duplicate creation or an invalid group review' do
    allocation = JrcRelationship::Assignment.create!(account: account, owner: actor, company: company)
    action = allocation.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Synthetic preserved responsibility',
                                        source_key: SecureRandom.uuid)
    post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { company_id: company.id, owner_id: actor.id } }
    expect(response).to have_http_status(:conflict)
    patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json, params: {
      assignment_ids: [allocation.id], active: true, expected_version: 0, reason: ''
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect([allocation.reload.owner_id, action.reload.owner_id, group.customer_links.count]).to eq([actor.id, actor.id, 0])
    expect(JrcRelationship::Assignment.where(account: account, company: company).count).to eq(1)
  end

  it 'does not use a master company parameter to read or allocate foreign tenant data' do
    foreign = create(:account)
    other = create(:user, account: foreign, role: :administrator)
    private_company = foreign.master_companies.create!(name: 'Foreign private customer', relationship_type: 'customer')
    JrcRelationship::Assignment.create!(account: foreign, owner: other, company: private_company)
    get "#{base}/portfolio", headers: headers, params: { company_id: private_company.id }
    expect(response.parsed_body.fetch('payload')).to eq([])
    expect do
      post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { company_id: private_company.id, owner_id: actor.id } }
    end.not_to change(JrcRelationship::Assignment, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'denies allocation without native manage authority and retains an already saved allocation when a later review loses group access' do
    role = account.custom_roles.create!(name: 'Synthetic native team viewer',
                                        permissions: %w[contact_manage jrc_relationship_view
                                                        jrc_relationship_team])
    viewer = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: viewer).update!(custom_role: role)
    expect do
      post "#{base}/portfolio", headers: viewer.create_new_auth_token, as: :json,
                                params: { assignment: { company_id: company.id, owner_id: viewer.id } }
    end.not_to change(JrcRelationship::Assignment, :count)
    expect(response).to have_http_status(:forbidden)
    allocation = JrcRelationship::Assignment.create!(account: account, owner: actor, company: company)
    patch "#{base}/portfolio_groups/#{group.id}/customers", headers: viewer.create_new_auth_token, as: :json, params: {
      assignment_ids: [allocation.id], active: true, expected_version: 0, reason: 'Cannot grant access from supplied parameters'
    }
    expect(response).to have_http_status(:forbidden)
    expect([allocation.reload.owner_id, group.customer_links.count]).to eq([actor.id, 0])
  end
end
