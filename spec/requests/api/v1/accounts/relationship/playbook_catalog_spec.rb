require 'rails_helper'

RSpec.describe 'Native paginated playbook catalog and stored history', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/playbooks" }
  let(:fields) do
    { name: 'Synthetic native book', trigger_kind: 'health', active: false, conditions: [],
      steps: [{ 'kind' => 'activity', 'title' => 'Native bounded task', 'after_days' => 0 }] }
  end
  let(:book) { JrcRelationship::Playbook.create!(fields.merge(account: account, version: 72)) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'pages beyond the legacy hundred-book bound while preserving the old unpaginated contract' do
    books = Array.new(103) { |index| JrcRelationship::Playbook.create!(fields.merge(account: account, name: "Synthetic #{index}")) }
    get base, headers: headers, params: { page: 5, per_page: 25 }
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('meta')).to eq('page' => 5, 'per_page' => 25, 'total' => 103)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq(books.last(3).map(&:id))
    expect(response.parsed_body.fetch('payload').first).not_to have_key('history')
    get base, headers: headers
    expect(response.parsed_body.fetch('payload').size).to eq(100)
    expect(response.parsed_body.fetch('payload').first).to have_key('history')
  end

  it 'pages stored versions beyond fifty and reads the exact historical source alongside the current book without writing' do
    72.times { |index| book.versions.create!(account: account, version: index + 1, payload: book.snapshot.merge('version' => index + 1)) }
    before = [book.attributes, book.versions.count, JrcCrm::AuditEvent.count]
    get "#{base}/#{book.id}/history", headers: headers, params: { page: 3, per_page: 25 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('version')).to eq(22.downto(1).to_a)
    expect(response.parsed_body.fetch('meta')).to eq('page' => 3, 'per_page' => 25, 'total' => 72)
    get "#{base}/#{book.id}/history", headers: headers, params: { source_version: 1 }
    expect(response.parsed_body.fetch('current').slice('id', 'version')).to eq('id' => book.id, 'version' => 72)
    expect(response.parsed_body.fetch('payload').pluck('version')).to eq([1])
    expect([book.reload.attributes, book.versions.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'bounds pages using the existing native paging rules and returns empty missing sources' do
    get "#{base}/#{book.id}/history", headers: headers, params: { page: -1, per_page: 100_000 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'per_page' => 50, 'total' => 0)
    get "#{base}/#{book.id}/history", headers: headers, params: { source_version: 999 }
    expect(response.parsed_body.fetch('payload')).to eq([])
    %w[0 -1 1.5 invalid].each do |value|
      get "#{base}/#{book.id}/history", headers: headers, params: { source_version: value }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'does not accept a foreign account override or disclose foreign books and versions' do
    foreign = create(:account)
    row = JrcRelationship::Playbook.create!(fields.merge(account: foreign, name: 'Foreign private definition'))
    get base, headers: headers, params: { page: 1, account_id: foreign.id }
    expect(response.parsed_body.fetch('payload')).to eq([])
    get "#{base}/#{row.id}/history", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Foreign private definition')
  end

  it 'retains native configure denial for both paginated catalog and history' do
    member = create(:user, account: account, role: :agent)
    native_headers = member.create_new_auth_token
    get base, headers: native_headers, params: { page: 1 }
    expect(response).to have_http_status(:forbidden)
    get "#{base}/#{book.id}/history", headers: native_headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(book.name)
  end
end
