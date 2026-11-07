require 'rails_helper'

RSpec.describe 'Visible native playbook execution history pagination', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/playbook_executions" }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:book) do
    JrcRelationship::Playbook.create!(account: account, name: 'Synthetic history', active: false, trigger_kind: 'health',
                                      steps: [{ 'kind' => 'activity', 'title' => 'Synthetic history step', 'after_days' => 0 }])
  end
  let(:attributes) do
    { account: account, assignment: allocation, playbook: book, actor: actor, version: 1, snapshot: book.snapshot,
      step_source_keys: [], source_key: 'synthetic-read-only-history' }
  end
  let(:history) do
    Array.new(103) { JrcRelationship::PlaybookExecution.create!(**attributes, execution_key: SecureRandom.hex(32)) }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'reaches older immutable executions beyond the legacy cap without duplicating visible rows' do
    expected = history.reverse.map(&:id)
    original = history.first.attributes
    get url, headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq(expected.first(100))
    ids = []
    cursor = nil
    3.times do
      get url, headers: headers, params: { per_page: 50, before_id: cursor }
      body = response.parsed_body
      ids.concat(body.fetch('payload').pluck('id'))
      cursor = body.fetch('meta').fetch('next_before_id')
    end
    expect(ids).to eq(expected)
    expect(cursor).to be_nil
    expect(history.first.reload.attributes).to eq(original)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(JrcFlowRun.where(account: account)).not_to exist
  end

  it 'passes source-denied candidates without leaking their names, IDs or counts into pagination metadata' do
    visible = JrcRelationship::PlaybookExecution.create!(**attributes, execution_key: SecureRandom.hex(32))
    hidden_snapshot = book.snapshot.merge('name' => 'Synthetic hidden source name',
                                          'results' => [{ 'resource_type' => 'UnsupportedPrivateSource', 'resource_id' => 9 }])
    Array.new(105) do
      JrcRelationship::PlaybookExecution.create!(**attributes, snapshot: hidden_snapshot, execution_key: SecureRandom.hex(32))
    end
    get url, headers: headers, params: { per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([visible.id])
    expect(response.parsed_body.fetch('meta')).to eq('per_page' => 1, 'next_before_id' => nil)
    expect(response.body).not_to include('Synthetic hidden source name', 'total', 'UnsupportedPrivateSource')
  end

  it 'keeps current configure, account and allocation scope for cursor reads' do
    saved = JrcRelationship::PlaybookExecution.create!(**attributes, execution_key: SecureRandom.hex(32))
    role = account.custom_roles.create!(name: 'Synthetic configure own roots',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_configure])
    member = account.account_users.find_by!(user: actor)
    member.update!(role: :agent, custom_role: role)
    other = create(:user, account: account, role: :agent)
    other_allocation = JrcRelationship::Assignment.create!(account: account, owner: other, contact: create(:contact, account: account))
    JrcRelationship::PlaybookExecution.create!(**attributes, assignment: other_allocation, actor: other, execution_key: SecureRandom.hex(32))
    get url, headers: headers, params: { per_page: 25, user_id: other.id, account_id: create(:account).id }
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([saved.id])
    member.update!(custom_role: nil)
    get url, headers: headers, params: { per_page: 25 }
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/accounts/#{create(:account).id}/relationship/playbook_executions", headers: headers, params: { per_page: 25 }
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects malformed cursor or size and restricts the optional book filter to the current account' do
    get url, headers: headers, params: { per_page: 'bad' }
    expect(response).to have_http_status(:unprocessable_entity)
    get url, headers: headers, params: { per_page: 25, before_id: ['1'] }
    expect(response).to have_http_status(:unprocessable_entity)
    foreign = JrcRelationship::Playbook.create!(account: create(:account), name: 'Foreign synthetic history', active: false, trigger_kind: 'health',
                                                steps: [{ 'kind' => 'activity', 'title' => 'Synthetic history step', 'after_days' => 0 }])
    get url, headers: headers, params: { per_page: 25, playbook_id: foreign.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'narrows to a selected native playbook and caps the requested page size without changing historical rows' do
    saved = JrcRelationship::PlaybookExecution.create!(**attributes, execution_key: SecureRandom.hex(32))
    other = JrcRelationship::Playbook.create!(account: account, name: 'Synthetic other book', active: false, trigger_kind: 'health',
                                              steps: book.steps)
    JrcRelationship::PlaybookExecution.create!(**attributes, playbook: other, execution_key: SecureRandom.hex(32))
    get url, headers: headers, params: { per_page: 500, playbook_id: book.id }
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([saved.id])
    expect(response.parsed_body.fetch('meta')).to eq('per_page' => 50, 'next_before_id' => nil)
  end

  it 'returns a controlled narrowing requirement rather than a false empty result when the scan budget is exhausted' do
    stub_const('JrcRelationship::PlaybookExecutionHistory::SCAN_LIMIT', 3)
    hidden = book.snapshot.merge('results' => [{ 'resource_type' => 'UnsupportedPrivateSource', 'resource_id' => 9 }])
    Array.new(4) do
      JrcRelationship::PlaybookExecution.create!(**attributes, snapshot: hidden, execution_key: SecureRandom.hex(32))
    end
    get url, headers: headers, params: { per_page: 25 }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('errors').sole).to include('Narrow the playbook filter')
    expect(response.parsed_body).not_to have_key('payload')
  end
end
