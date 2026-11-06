require 'rails_helper'

RSpec.describe 'Native operational period filter integrity', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rejects incomplete operational periods on both dashboard and native action lists without returning unfiltered results' do
    ['/dashboard', '/records/actions'].each do |suffix|
      get "#{base}#{suffix}", headers: headers, params: { to: '2026-10-01' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('errors').join).to include('start date')
      expect(response.parsed_body.fetch('code')).to eq('INVALID_OPERATIONAL_PERIOD')
      expect(response.parsed_body).not_to include('payload', 'customers', 'meta')
    end
  end

  it 'uses the same local day for real pagination and keeps source records intact when filters are removed' do
    moments = [Time.utc(2026, 10, 1, 2, 59, 59), Time.utc(2026, 10, 1, 3),
               Time.utc(2026, 10, 2, 2, 59, 59), Time.utc(2026, 10, 2, 3)]
    actions = moments.map do |moment|
      JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'manual',
                                      reason: 'Synthetic local-day action', source_key: SecureRandom.uuid, due_at: moment)
    end
    before = actions.map(&:attributes)
    selected = [1, 2].flat_map do |page|
      get "#{base}/records/actions", headers: headers, params: { from: '2026-10-01', per_page: 1, page: page }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'page' => page)
      response.parsed_body.fetch('payload').pluck('id')
    end
    expect(selected).to eq(actions[1..2].map(&:id))
    get "#{base}/records/actions", headers: headers
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(4)
    expect(actions.map { |row| row.reload.attributes }).to eq(before)
  end

  it 'keeps tenant authorization ahead of period validation and never grants records through a selected foreign assignment' do
    foreign = create(:account)
    outsider = create(:user, account: foreign, role: :administrator)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, owner: outsider, contact: create(:contact, account: foreign))
    get "#{base}/dashboard", headers: outsider.create_new_auth_token, params: { to: '2026-10-01' }
    expect(response).to have_http_status(:forbidden)
    get "#{base}/records/actions", headers: headers, params: { from: '2026-10-01', assignment_id: foreign_assignment.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
  end

  it 'returns the existing validation response for malformed dates and arrays rather than an internal parser error' do
    [{ from: ['2026-10-01'] }, { from: '2026-02-30' }, { from: '2026-10-02', to: '2026-10-01' }].each do |values|
      get "#{base}/records/actions", headers: headers, params: values
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('code')).to eq('INVALID_OPERATIONAL_PERIOD')
      expect(response.parsed_body).not_to have_key('payload')
    end
  end
end
