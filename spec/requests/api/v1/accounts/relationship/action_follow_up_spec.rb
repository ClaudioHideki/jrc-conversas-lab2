require 'rails_helper'

RSpec.describe 'Relationship analyst follow-up', type: :request do
  let(:account) { create(:account) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:headers) { analyst.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/records/actions" }
  let!(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst) }
  let!(:action) do
    JrcRelationship::Action.create!(account: account, assignment: assignment, owner: analyst, kind: 'manual',
                                    reason: 'SYNTHETIC customer follow-up', source_key: 'synthetic-follow-up', priority: 80)
  end
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'persists the result, return and explicit customer response with the authenticated actor and an audited history' do
    due = 2.days.from_now.change(usec: 0)
    patch "#{url}/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, status: 'in_progress', result: 'Contacted through native channel',
      next_step: 'Confirm stable service', return_at: due.iso8601, customer_confirmation: 'confirmed', customer_feedback: 'Customer confirmed recovery',
      customer_confirmed_by_id: manager.id, account_id: -1
    } }
    expect(response).to have_http_status(:ok)
    expect(action.reload).to have_attributes(next_step: 'Confirm stable service', return_at: due,
                                              customer_confirmed_by_id: analyst.id, customer_confirmation: 'confirmed')
    expect(action.customer_confirmed_at).to be_present
    expect(action.activity).to have_attributes(due_at: due, user_id: analyst.id)
    get "#{url}/#{action.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['history'].first).to include('actor_id' => analyst.id)
    expect(response.parsed_body['history'].first.dig('after', 'next_step')).to eq('Confirm stable service')
    expect(response.parsed_body).not_to have_key('account_id')
  end

  it 'keeps confirmation pending after a technical completion without a customer response' do
    patch "#{url}/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, status: 'completed', result: 'Technical area resolved the incident'
    } }
    expect(response).to have_http_status(:ok)
    expect(action.reload).to have_attributes(status: 'completed', customer_confirmation: 'pending', customer_confirmed_at: nil)
  end

  it 'rejects a claimed customer response without evidence and rolls back the entire update' do
    patch "#{url}/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, customer_confirmation: 'confirmed', result: 'Attempted update'
    } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(action.reload).to have_attributes(customer_confirmation: 'pending', result: nil, customer_confirmed_by_id: nil)
  end

  it 'requires a next step for a scheduled return and rejects stale writes' do
    patch "#{url}/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, return_at: 1.day.from_now.iso8601
    } }
    expect(response).to have_http_status(:unprocessable_entity)
    version = action.lock_version
    action.update!(reason: 'Changed by another session')
    patch "#{url}/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: version, result: 'Stale result'
    } }
    expect(response).to have_http_status(:conflict)
    expect(action.reload.result).to be_nil
  end

  it 'denies another portfolio, another account and access revoked by reassignment' do
    foreign = create(:account)
    foreign_assignment = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    foreign_action = JrcRelationship::Action.create!(account: foreign, assignment: foreign_assignment, kind: 'manual',
                                                    reason: 'Private', source_key: 'private')
    get "#{url}/#{foreign_action.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    assignment.update!(owner: manager)
    get "#{url}/#{action.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    patch "#{url}/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, next_step: 'Unauthorized', return_at: 1.day.from_now.iso8601
    } }
    expect(response).to have_http_status(:not_found)
    expect(action.reload.next_step).to be_nil
  end

  it 'filters my actions by the action owner and paginates within the authorized scope' do
    action.update!(owner: manager)
    get url, headers: headers, as: :json, params: { mine: true }
    expect(response.parsed_body['payload']).to eq([])
    action.update!(owner: analyst, next_step: 'Return', return_at: 1.hour.ago)
    get url, headers: headers, as: :json, params: { mine: true, returns_overdue: true, per_page: 500 }
    expect(response.parsed_body['payload'].pluck('id')).to eq([action.id])
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(50)
    get url, headers: headers, as: :json, params: { mine: true, page: 2, per_page: 1 }
    expect(response.parsed_body['payload']).to eq([])
    expect(response.parsed_body['meta']).to include('page' => 2, 'total' => 1)
  end
end
