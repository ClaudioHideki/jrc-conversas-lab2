require 'rails_helper'

RSpec.describe 'Native analyst workspace indicator sources', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:other) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:headers) { actor.create_new_auth_token }
  let(:mine) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:theirs) { JrcRelationship::Assignment.create!(account: account, owner: other, contact: create(:contact, account: account)) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'matches today and return counters with real active unpaused sources under portfolio ownership rather than action ownership' do
    travel_to(Time.utc(2026, 11, 6, 2, 30)) do
      due = Time.utc(2026, 11, 6, 2, 45)
      source = mine.actions.create!(account: account, owner: other, kind: 'manual', reason: 'Delegated current portfolio work',
                                    source_key: 'today', due_at: due)
      theirs.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Owned task on another portfolio',
                             source_key: 'other-root', due_at: due)
      mine.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Completed history', source_key: 'completed', due_at: due,
                           status: 'completed', result: 'Already complete', completed_at: Time.current, completed_by: actor)
      returning = mine.actions.create!(account: account, owner: other, kind: 'manual', reason: 'Native overdue return', source_key: 'return',
                                       due_at: 1.day.from_now, next_step: 'Review evidence', return_at: 1.hour.ago)
      waiting = { assignment_id: mine.id, owner_id: actor.id, request_id: SecureRandom.uuid, reason: 'Paused awaiting source', due_at: due,
                  status: 'waiting_customer', waiting_reason: 'Waiting for customer evidence', next_step: 'Reassess', return_at: 3.hours.from_now }
      paused = JrcRelationship::Workflow.new(context).save(kind: 'actions', attributes: waiting).fetch(:record)
      expect(paused.reload.sla_paused_at).to be_present
      get "#{base}/dashboard", headers: headers, params: { mode: 'mine' }
      expect(response).to have_http_status(:ok), response.body
      metrics = response.parsed_body
      expected = { 'customers' => [mine.id], 'actions_today' => [source.id], 'overdue_returns' => [returning.id],
                   'waiting_customer_actions' => [paused.id] }
      expected.each do |metric, ids|
        get "#{base}/drilldown", headers: headers, params: { metric: metric, mode: 'mine' }
        expect(response).to have_http_status(:ok), response.body
        body = response.parsed_body
        expect([body.fetch('value'), body.fetch('total'), body.fetch('payload').pluck('id')]).to eq([metrics.fetch(metric), ids.length, ids])
      end
    end
  end

  it 'opens the exact authorized delegated action instead of an unrelated health screen or an owner-filtered list' do
    source = mine.actions.create!(account: account, owner: other, kind: 'manual', reason: 'Exact original workflow',
                                  source_key: 'delegated', return_at: 1.hour.ago.change(usec: 0), next_step: 'Reassess')
    get "#{base}/records/actions", headers: headers, params: { mine: 'true' }
    expect(response.parsed_body.fetch('payload').pluck('id')).not_to include(source.id)
    get "#{base}/drilldown", headers: headers, params: { metric: 'overdue_returns', mode: 'mine' }
    expect(response).to have_http_status(:ok), response.body
    route = response.parsed_body.fetch('payload').sole.fetch('route')
    expect(Time.iso8601(response.parsed_body.fetch('payload').sole.fetch('date'))).to eq(source.return_at)
    expect(route).to eq('name' => 'jrc_relationship_actions', 'params' => { 'accountId' => account.id },
                        'query' => { 'action_id' => source.id, 'mine' => 'false' })
    get "#{base}/records/actions/#{route.fetch('query').fetch('action_id')}", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('id' => source.id, 'owner_id' => other.id)
  end

  it 'drills into the latest authorized risk measurement in the same selected portfolio' do
    [mine, theirs].each do |assignment|
      JrcRelationship::HealthSnapshot.create!(account: account, assignment: assignment, viewer: actor, config_scope_key: 'account', config_version: 1,
                                              access_signature: context.access_signature, fingerprint: SecureRandom.hex(32), score: 30,
                                              band: 'risk', factors: [],
                                              signals: { _source_ids: {}, days_without_contact: 0 }, calculated_at: Time.current)
    end
    get "#{base}/dashboard", headers: headers, params: { mode: 'mine' }
    expect(response.parsed_body.fetch('at_risk')).to eq(1)
    get "#{base}/drilldown", headers: headers, params: { mode: 'mine', metric: 'at_risk' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('value' => 1, 'total' => 1)
    expect(response.parsed_body.fetch('payload').pluck('assignment_id')).to eq([mine.id])
  end

  it 'paginates the actual source set and cannot grant a foreign tenant or survive native module revocation' do
    26.times do |index|
      mine.actions.create!(account: account, owner: other, kind: 'manual', reason: "Native return #{index}", source_key: "page-#{index}",
                           next_step: 'Review', return_at: 1.hour.ago)
    end
    get "#{base}/drilldown", headers: headers, params: { metric: 'overdue_returns', mode: 'mine', page: 2 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('value' => 26, 'total' => 26, 'page' => 2, 'per_page' => 25)
    expect(response.parsed_body.fetch('payload').length).to eq(1)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/drilldown", headers: headers,
                                                                 params: { metric: 'overdue_returns', account_id: account.id }
    expect(response).to have_http_status(:forbidden)
    account.disable_features!('jrc_relationship')
    get "#{base}/drilldown", headers: headers, params: { metric: 'overdue_returns' }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('payload', 'Native return')
  end
end
