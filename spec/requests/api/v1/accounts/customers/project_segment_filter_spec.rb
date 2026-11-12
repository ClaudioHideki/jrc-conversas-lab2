require 'rails_helper'

RSpec.describe 'Published customer segments in native Projects reads', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/projects" }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Project customers', kind: 'segment', modules: ['projects']) }
  let(:company) { account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:other_contact) { create(:contact, account: account) }
  let(:selected) do
    JrcProjects::Projects::Create.call(account: account, actor: actor, idempotency_key: SecureRandom.uuid,
                                       attributes: { name: 'Selected project', contact_id: contact.id, visibility: 'private' })
  end
  let(:unmatched) do
    JrcProjects::Projects::Create.call(account: account, actor: actor, idempotency_key: SecureRandom.uuid,
                                       attributes: { name: 'Other project', contact_id: other_contact.id, visibility: 'private' })
  end
  let(:hidden) do
    JrcProjects::Projects::Create.call(account: account, actor: colleague, idempotency_key: SecureRandom.uuid,
                                       attributes: { name: 'Hidden project', contact_id: contact.id, visibility: 'private' })
  end
  let(:shared) do
    JrcProjects::Projects::Create.call(account: account, actor: colleague, idempotency_key: SecureRandom.uuid,
                                       attributes: { name: 'Shared project', contact_id: contact.id, visibility: 'account' })
  end

  before do
    account.enable_features!('jrc_projects', 'jrc_customer_master')
    [actor, colleague].each do |user|
      account.account_users.find_by!(user: user).update!(jrc_projects_enabled: true,
                                                        jrc_projects_permissions: { 'projects.project.create' => true })
    end
    account.account_users.find_by!(user: actor).update!(jrc_projects_permissions: {
      'projects.project.create' => true, 'projects.report.view' => true
    })
    selected
    unmatched
    hidden
    shared
  end

  it 'narrows the native project scope without exposing private projects or modifying records' do
    get "#{root}/projects", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to contain_exactly(selected.id, unmatched.id, shared.id)
    original = [selected, unmatched, hidden, shared].map(&:attributes)
    get "#{root}/projects", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to contain_exactly(selected.id, shared.id)
    expect([selected, unmatched, hidden, shared].map { |project| project.reload.attributes }).to eq(original)
  end

  it 'calculates portfolio and task indicators over the same authorized segment' do
    member = account.account_users.find_by!(user: actor)
    JrcProjects::Tasks::Create.call(account_user: member, project: selected, attributes: { title: 'Selected task' })
    JrcProjects::Tasks::Create.call(account_user: member, project: unmatched, attributes: { title: 'Excluded task' })
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to include('total' => 2, 'tasks_total' => 1, 'scope' => 'visible_projects')
    expect(response.parsed_body.dig('data', 'filter_options', 'contacts').pluck('id')).to eq([contact.id])
  end

  it 'paginates inside the authorized segment and does not trust forged identity selectors' do
    get "#{root}/projects", headers: headers,
                            params: { customer_segment_id: taxonomy.id, page: 2, per_page: 1, user_id: colleague.id, unit_id: 0 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([selected.id])
    expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'page' => 2)
  end

  it 'retains explicit contact exclusions without falling back to the matching company' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: contact, mode: 'exclude')
    get "#{root}/projects", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to eq([])
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response.parsed_body.fetch('data')).to include('total' => 0, 'tasks_total' => 0)
  end

  it 'keeps native show authorization independent from the list selector' do
    get "#{root}/projects/#{unmatched.id}", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'id')).to eq(unmatched.id)
    get "#{root}/projects/#{hidden.id}", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'requires Directory for the extra filter while preserving the native project-only role' do
    role = create(:custom_role, account: account, permissions: ['jrc_projects_project_view'])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    get "#{root}/projects", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to include(selected.id)
    get "#{root}/projects", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rechecks native project membership flags rather than accepting a valid segment as a grant' do
    account.account_users.find_by!(user: actor).update!(jrc_projects_enabled: false)
    get "#{root}/projects", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:forbidden)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects a foreign segment even with memberships in both accounts' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: actor, role: :administrator)
    segment = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign projects', kind: 'segment', modules: ['projects'])
    get "#{root}/projects", headers: headers, params: { customer_segment_id: segment.id, account_id: foreign.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'rechecks publication and active status on each read' do
    taxonomy.update!(modules: ['crm'])
    get "#{root}/projects", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
    taxonomy.update!(modules: ['projects'], active: false)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
  end
end
