require 'rails_helper'

RSpec.describe 'Bounded native CRM calendar pages', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:jrc_crm_lead, account: account, owner: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/activities" }
  let(:window) { { calendar_page: 1, starts_on: '2026-11-01', ends_before: '2026-12-01', page: 1, per_page: 2 } }
  let!(:activities) do
    Array.new(3) do |index|
      create(:jrc_crm_activity, account: account, user: actor, lead: lead, deal: nil,
                               title: "Synthetic calendar #{index}", due_at: Time.utc(2026, 11, 7, 12))
    end
  end

  before { account.enable_features!('jrc_crm') }

  it 'preserves the existing array contract for clients without pagination parameters' do
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to be_an(Array)
    expect(response.parsed_body.map { |row| row['id'] }).to include(*activities.map(&:id))
    get url, headers: headers, params: { page: 2 }
    expect(response.parsed_body).to be_an(Array)
  end

  it 'returns a bounded stable page and authorized count with no-store' do
    get url, headers: headers, params: window
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].map { |row| row['id'] }).to eq(activities.map(&:id).sort.first(2))
    expect(response.parsed_body['meta']).to include('total' => 3, 'page' => 1, 'per_page' => 2, 'pages' => 2)
    expect(response.headers['Cache-Control']).to include('no-store')
    get url, headers: headers, params: window.merge(page: 2)
    expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([activities.map(&:id).max])
  end

  it 'does not include another owner in rows or total and preserves the native user filter' do
    other = create(:user, account: account, role: :agent)
    other_lead = create(:jrc_crm_lead, account: account, owner: other)
    create(:jrc_crm_activity, account: account, user: other, lead: other_lead, deal: nil, due_at: Time.utc(2026, 11, 7, 12))
    get url, headers: headers, params: window
    expect(response.parsed_body['meta']['total']).to eq(3)
    get url, headers: headers, params: window.merge(user_id: other.id)
    expect(response.parsed_body['data']).to eq([])
    expect(response.parsed_body['meta']['total']).to eq(0)
  end

  it 'enforces the inclusive start and exclusive end in the account time zone' do
    before_start = create(:jrc_crm_activity, account: account, user: actor, lead: lead, deal: nil, due_at: Time.utc(2026, 11, 1, 2, 59, 59))
    at_start = create(:jrc_crm_activity, account: account, user: actor, lead: lead, deal: nil, due_at: Time.utc(2026, 11, 1, 3))
    at_end = create(:jrc_crm_activity, account: account, user: actor, lead: lead, deal: nil, due_at: Time.utc(2026, 12, 1, 3))
    get url, headers: headers, params: window.merge(per_page: 100)
    ids = response.parsed_body['data'].map { |row| row['id'] }
    expect(ids).to include(at_start.id)
    expect(ids).not_to include(before_start.id, at_end.id)
  end

  it 'rejects invalid typed input rather than rendering the unbounded legacy list' do
    [{ calendar_page: 'false' }, { page: 'false' }, { page: ['1'] }, { per_page: 101 }, { starts_on: '2026-02-30' },
     { ends_before: '2026-10-01' }, { ends_before: '2028-01-01' }].each do |input|
      get url, headers: headers, params: window.merge(input)
      expect(response).to have_http_status(:unprocessable_entity), response.body
      expect(response.parsed_body['code']).to eq('INVALID_CALENDAR_QUERY')
    end
  end

  it 'rejects incomplete periods and expired access before returning private data' do
    get url, headers: headers, params: { calendar_page: 1, page: 1 }
    expect(response).to have_http_status(:unprocessable_entity)
    account.disable_features!('jrc_crm')
    get url, headers: headers, params: window
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies an actor from another account without disclosing a count' do
    outsider = create(:user, account: create(:account), role: :administrator)
    get url, headers: outsider.create_new_auth_token, params: window
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('meta')
  end
  it 'applies search before counting or paging, including matches outside page one' do
    activities.last.update!(title: 'Unique last-page search target')
    get url, headers: headers, params: window.merge(search: 'last-page search')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([activities.last.id])
    expect(response.parsed_body['meta']['total']).to eq(1)
  end

  it 'does not interpret LIKE metacharacters as a request for all records' do
    get url, headers: headers, params: window.merge(search: '%_')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['meta']['total']).to eq(0)
  end

  it 'combines native activity type with completion state before paging' do
    activities.first.update!(activity_type: 'call', status: 'completed', completed_at: Time.current)
    get url, headers: headers, params: window.merge(activity_type: 'call', status: 'completed')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].map { |row| row['id'] }).to eq([activities.first.id])
  end

  it 'validates filters instead of falling back to an unbounded response' do
    [{ search: ['private'] }, { activity_type: 'unknown' }, { status: 'any' }, { user_id: 'false' }].each do |input|
      get url, headers: headers, params: window.merge(input)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).not_to have_key('data')
    end
  end

  it 'offers owners only through the authorized period, not the global account directory' do
    other = create(:user, account: account, role: :agent)
    get url, headers: headers, params: window.merge(include_owners: '1')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['owners'].map { |row| row['id'] }).to eq([actor.id])
    expect(response.parsed_body['owners'].map { |row| row['id'] }).not_to include(other.id)
  end

  it 'does not create or update activities during a paginated read' do
    before = account.jrc_crm_activities.order(:id).pluck(:id, :updated_at, :user_id)
    get url, headers: headers, params: window.merge(include_owners: '1', status: 'open')
    expect(response).to have_http_status(:ok)
    expect(account.jrc_crm_activities.order(:id).pluck(:id, :updated_at, :user_id)).to eq(before)
  end

end
