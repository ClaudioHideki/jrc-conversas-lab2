require 'rails_helper'

RSpec.describe 'Named relationship portfolios', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic operational portfolio') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:reason) { 'Synthetic reviewed customer grouping; preserve all original ownership' }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'creates and edits an actual named portfolio with explicit goals and optimistic revision' do
    post "#{base}/portfolio_groups", headers: headers, as: :json, params: {
      portfolio_group: { name: 'Synthetic customer success portfolio', objective: 'Monitor the existing customers',
                         goals: [{ metric: 'Measured coverage', target: 80, current: 65, unit: 'percent' }] }
    }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    patch "#{base}/portfolio_groups/#{id}", headers: headers, as: :json,
                                            params: { portfolio_group: { objective: 'Updated measured goal' }, expected_version: 0, reason: reason }
    expect(response).to have_http_status(:ok)
    get "#{base}/portfolio_groups/#{id}", headers: headers
    expect(response.parsed_body).to include('objective' => 'Updated measured goal', 'version' => 1, 'customer_count' => 0)
    expect(response.parsed_body.fetch('goals')).to include(include('metric' => 'Measured coverage', 'target' => 80))
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'links one real allocation into multiple active portfolios and counts it once globally' do
    assignment
    original = assignment.attributes
    second = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic second operational portfolio')
    [group, second].each do |portfolio|
      patch "#{base}/portfolio_groups/#{portfolio.id}/customers", headers: headers, as: :json,
                                                                  params: { assignment_ids: [assignment.id], active: true,
                                                                            expected_version: 0, reason: reason }
      expect([response.status, response.parsed_body.fetch('version')]).to eq([200, 1])
    end
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('customers')).to eq(1)
    expect(assignment.reload.attributes).to eq(original)
    expect(JrcRelationship::PortfolioGroupAssignment.where(account: account, assignment: assignment, active: true).count).to eq(2)
  end

  it 'preserves membership history when a customer link is deactivated' do
    link = JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json,
                                                            params: { assignment_ids: [assignment.id], active: false,
                                                                      expected_version: 0, reason: reason }
    expect(response).to have_http_status(:ok)
    expect(link.reload).to have_attributes(active: false, assignment_id: assignment.id)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'does not apply stale metadata or customer link edits and creates no false audit receipt' do
    group
    group.update!(objective: 'Newer revision')
    original = JrcCrm::AuditEvent.count
    patch "#{base}/portfolio_groups/#{group.id}", headers: headers, as: :json,
                                                  params: { portfolio_group: { objective: 'Stale edit' }, expected_version: 0, reason: reason }
    expect(response).to have_http_status(:conflict)
    patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json,
                                                            params: { assignment_ids: [assignment.id], active: true,
                                                                      expected_version: 0, reason: reason }
    expect(response).to have_http_status(:conflict)
    expect([group.reload.objective, group.customer_links.count, JrcCrm::AuditEvent.count]).to eq(['Newer revision', 0, original])
  end

  it 'keeps hidden customer totals unavailable and grants no customer access through an account-visible group' do
    group.update!(visibility: 'account')
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    viewer = create(:user, account: account, role: :agent)
    get "#{base}/portfolio_groups/#{group.id}", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('customer_count' => nil, 'visible_customer_count' => 0, 'access_limited' => true)
    get "#{base}/portfolio_groups/#{group.id}/customers", headers: viewer.create_new_auth_token
    expect(response.parsed_body.fetch('payload')).to eq([])
    expect(response.body).not_to include(assignment.label)
  end

  it 'rolls back coordination transfer when the destination cannot view the existing native customer' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    target = create(:user, account: account, role: :agent)
    original = JrcCrm::AuditEvent.count
    patch "#{base}/portfolio_groups/#{group.id}", headers: headers, as: :json,
                                                  params: { portfolio_group: { owner_id: target.id }, expected_version: 0, reason: reason }
    expect(response).to have_http_status(:forbidden)
    expect([group.reload.owner_id, group.lock_version, assignment.reload.owner_id, JrcCrm::AuditEvent.count])
      .to eq([actor.id, 0, actor.id, original])
  end

  it 'denies cross-account customer links without creating a membership or changing the group revision' do
    foreign = create(:account)
    other = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json,
                                                            params: { assignment_ids: [other.id], active: true,
                                                                      expected_version: 0, reason: reason, account_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    expect([group.customer_links.count, group.reload.lock_version]).to eq([0, 0])
  end

  it 'preserves customer ownership and links when a portfolio is archived' do
    link = JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    original = assignment.attributes
    patch "#{base}/portfolio_groups/#{group.id}", headers: headers, as: :json,
                                                  params: { portfolio_group: { status: 'archived' }, expected_version: 0, reason: reason }
    expect(response).to have_http_status(:ok)
    expect([group.reload.status, link.reload.active?, assignment.reload.attributes]).to eq(['archived', true, original])
  end

  it 'paginates named portfolios and removes the text filter without losing the original account scope' do
    portfolios = Array.new(26) do |index|
      JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: "Synthetic cohort #{index.to_s.rjust(2, '0')}")
    end
    get "#{base}/portfolio_groups", headers: headers, params: { page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('total' => 26, 'page' => 2, 'per_page' => 25)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([portfolios.last.id])
    get "#{base}/portfolio_groups", headers: headers, params: { q: 'cohort 04' }
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([portfolios[4].id])
    get "#{base}/portfolio_groups", headers: headers, params: { q: '' }
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(26)
  end

  it 'paginates only the actual authorized native customers of the selected portfolio' do
    customers = Array.new(26) do
      row = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
      JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: row)
      row
    end
    get "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, params: { page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('total' => 26, 'page' => 2, 'per_page' => 25)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([customers.last.id])
  end

  it 'denies private portfolio metadata and writes by an ordinary viewer without granting team permissions' do
    viewer = create(:user, account: account, role: :agent)
    get "#{base}/portfolio_groups/#{group.id}", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(group.name)
    expect do
      post "#{base}/portfolio_groups", headers: viewer.create_new_auth_token, as: :json,
                                       params: { portfolio_group: { name: 'Forbidden ordinary viewer creation' } }
    end.not_to change(JrcRelationship::PortfolioGroup, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not turn account-wide metadata visibility into write access for an unrelated scoped supervisor' do
    permissions = %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team jrc_relationship_configure]
    role = create(:custom_role, account: account, permissions: permissions)
    supervisor = create(:user, account: account, role: :agent)
    supervisor_member = account.account_users.find_by!(user: supervisor)
    supervisor_member.update!(custom_role: role)
    policy = JrcRelationship::Context.new(supervisor_member).policy
    expect([policy.manage?, policy.team?, policy.configure?]).to eq([true, true, true])
    group.update!(visibility: 'account')
    get "#{base}/portfolio_groups/#{group.id}", headers: supervisor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('can_manage' => false, 'can_configure' => false)
    patch "#{base}/portfolio_groups/#{group.id}", headers: supervisor.create_new_auth_token, as: :json,
                                                  params: { portfolio_group: { objective: 'Unrelated supervisor edit' },
                                                            expected_version: group.lock_version,
                                                            reason: reason }
    expect(response).to have_http_status(:not_found)
    expect(group.reload.objective).to eq('')
  end

  it 'does not assign active coordination to a view-only CS role or add privileges to that role' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view])
    viewer = create(:user, account: account, role: :agent)
    membership = account.account_users.find_by!(user: viewer)
    membership.update!(custom_role: role)
    original = membership.reload.attributes
    policy = JrcRelationship::Context.new(membership).policy
    expect([policy.access?, policy.manage?]).to eq([true, false])
    expect do
      post "#{base}/portfolio_groups", headers: headers, as: :json,
                                       params: { portfolio_group: { name: 'Unsupported readonly coordination', owner_id: viewer.id } }
    end.not_to change(JrcRelationship::PortfolioGroup, :count)
    expect(response).to have_http_status(:forbidden)
    expect(membership.reload.attributes).to eq(original)
  end

  it 'advances the portfolio revision for association changes even when the request clock has not advanced' do
    travel_to(Time.current.change(usec: 0)) do
      group
      assignment
      patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json,
                                                              params: { assignment_ids: [assignment.id], active: true,
                                                                        expected_version: 0, reason: reason }
      expect([response.status, response.parsed_body.fetch('version')]).to eq([200, 1])
      patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json,
                                                              params: { assignment_ids: [assignment.id], active: false,
                                                                        expected_version: 1, reason: reason }
      expect([response.status, response.parsed_body.fetch('version')]).to eq([200, 2])
      expect(group.customer_links.find_by!(assignment: assignment).active?).to be(false)
    end
  end

  it 'denies foreign group metadata and customer queries despite forged account and actor parameters' do
    foreign = create(:account)
    other = create(:user, account: foreign, role: :administrator)
    foreign_group = JrcRelationship::PortfolioGroup.create!(account: foreign, owner: other, name: 'Foreign private group')
    ["#{base}/portfolio_groups/#{foreign_group.id}", "#{base}/portfolio_groups/#{foreign_group.id}/customers"].each do |url|
      get url, headers: headers, params: { account_id: foreign.id, user_id: other.id }
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(foreign_group.name)
    end
    get "#{base}/portfolio_groups", headers: headers, params: { account_id: foreign.id, user_id: other.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq([])
  end

  it 'keeps administrator group metadata inside native operator and unit coverage' do
    operator = account.master_companies.create!(name: 'Synthetic portfolio operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic portfolio unit #{index}", code: SecureRandom.hex(6), company_id: operator.id)
    end
    group.update!(business_unit: units.last, visibility: 'account')
    allowed = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Allowed unit group', business_unit: units.first)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: operator,
                                                business_unit: units.first, active: true, structure_managed: true)
    get "#{base}/portfolio_groups/#{group.id}", headers: headers, params: { unit_id: units.last.id, business_unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
    get "#{base}/portfolio_groups", headers: headers, params: { business_unit_id: units.last.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([allowed.id])
  end

  it 'rolls back customer links from an incompatible unit without changing the native customer' do
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic customer unit #{index}", code: SecureRandom.hex(6))
    end
    group.update!(business_unit: units.first)
    assignment.update!(business_unit: units.last)
    original = assignment.reload.attributes
    patch "#{base}/portfolio_groups/#{group.id}/customers", headers: headers, as: :json,
                                                            params: { assignment_ids: [assignment.id], active: true,
                                                                      expected_version: 1, reason: reason }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(group.customer_links).to be_empty
    expect(group.reload.lock_version).to eq(1)
    expect(assignment.reload.attributes).to eq(original)
  end

  [false, [], {}].each do |owner|
    it "rejects invalid coordinator shape #{owner.inspect} before creating a default-owned portfolio" do
      expect do
        post "#{base}/portfolio_groups", headers: headers, as: :json,
                                         params: { portfolio_group: { name: 'Invalid owner input', owner_id: owner } }
      end.not_to change(JrcRelationship::PortfolioGroup, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
