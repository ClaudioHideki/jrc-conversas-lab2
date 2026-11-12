require 'rails_helper'

RSpec.describe 'Current native playbook execution read access', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/playbook_executions" }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:book) do
    JrcRelationship::Playbook.create!(account: account, name: 'Synthetic saved definition', trigger_kind: 'health', active: false,
                                      steps: [{ 'kind' => 'activity', 'title' => 'Synthetic native step', 'after_days' => 0 }])
  end
  let(:execution) do
    JrcRelationship::PlaybookExecution.create!(account: account, assignment: allocation, playbook: book, actor: actor,
                                               version: book.version, source_key: 'synthetic-historical-origin', execution_key: SecureRandom.hex(32),
                                               snapshot: book.snapshot, step_source_keys: [])
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'returns only the native saved projection with no-store and no mutation of the historical row' do
    before = execution.attributes
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([execution.id])
    expect(response.parsed_body.fetch('payload').first.fetch('snapshot').fetch('results')).to eq([])
    expect(execution.reload.attributes).to eq(before)
    expect(JrcFlowRun.where(account: account)).not_to exist
  end

  it 'rechecks native configure permission on each request after the same member loses it' do
    execution
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(book.name)
    expect(JrcRelationship::PlaybookExecution.where(id: execution.id)).to exist
  end

  it 'does not let configure permission broaden native allocation visibility or switch the account through query input' do
    execution
    other = create(:user, account: account, role: :agent)
    other_allocation = JrcRelationship::Assignment.create!(account: account, owner: other, contact: create(:contact, account: account))
    hidden = JrcRelationship::PlaybookExecution.create!(account: account, assignment: other_allocation, playbook: book, actor: other,
                                                        version: 1, source_key: 'synthetic-other-owner', execution_key: SecureRandom.hex(32),
                                                        snapshot: book.snapshot.merge('name' => 'Hidden other-owner definition'),
                                                        step_source_keys: [])
    role = account.custom_roles.create!(name: 'Synthetic configure own portfolio',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_configure])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    get url, headers: headers, params: { account_id: create(:account).id, user_id: other.id, assignment_id: other_allocation.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([execution.id])
    expect(response.body).not_to include('Hidden other-owner definition')
    expect(hidden.reload.snapshot.fetch('name')).to eq('Hidden other-owner definition')
  end
end
