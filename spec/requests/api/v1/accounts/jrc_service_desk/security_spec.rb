# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'JRC Service Desk CP4 request boundaries', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:row) { sd_ticket }
  def denied!
    expect([401, 403, 404, 422]).to include(response.status)
    expect(response.body).not_to include('cross-boundary secret')
  end

  it 'denies another Account even when the route is manipulated' do
    other = create(:jrc_sd_ticket, unit: sd_foreign_unit, title: 'cross-boundary secret')
    get "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk/tickets/#{other.id}", headers: headers
    denied!
    get "#{base}/tickets/#{other.id}", headers: headers
    denied!
  end

  it 'denies an agent a same-Account ticket from an ungranted unit' do
    hidden = create(:jrc_sd_ticket, unit: sd_other_unit, title: 'cross-boundary secret')
    get "#{base}/tickets/#{hidden.id}", headers: headers
    denied!
    get "#{base}/tickets", headers: headers, params: { unit_id: sd_other_unit.id }
    denied!
  end

  %w[ui_context tickets dashboard queues units operator_companies].each do |endpoint|
    it "denies #{endpoint} to an agent with no active UnitMembership" do
      sd_membership.update!(active: false)
      get "#{base}/#{endpoint}", headers: headers
      denied!
    end
    it "denies #{endpoint} with the feature switched off" do
      sd_account.disable_features!('jrc_service_desk')
      get "#{base}/#{endpoint}", headers: headers
      denied!
    end
  end

  it 'rechecks revocation between real requests, discarding prior authorization' do
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    sd_membership.update!(active: false)
    patch "#{base}/tickets/#{row.id}", headers: headers, as: :json,
      params: { ticket: { title: 'Must not persist' }, expected_lock_version: row.lock_version }
    denied!
    expect(row.reload.title).to eq('Test ticket')
  end

  it 'rejects both foreign operators and foreign units in selectors' do
    [{ unit_id: sd_foreign_unit.id }, { operator_company_id: sd_foreign_operator.id }].each do |filters|
      get "#{base}/tickets", headers: headers, params: filters
      denied!
      get "#{base}/dashboard", headers: headers, params: filters
      denied!
    end
  end

  it 'rejects foreign and ungranted unit create requests without creating a fallback unit' do
    denied_units = [sd_other_unit, sd_foreign_unit]
    original_units = JrcServiceDesk::Unit.count
    denied_units.each do |unit|
      post "#{base}/tickets", headers: headers.merge('Idempotency-Key' => "bad-unit-#{unit.id}"), as: :json,
        params: { unit_id: unit.id, ticket: sd_create_attributes }
      denied!
    end
    expect(JrcServiceDesk::Ticket.count).to eq(0)
    expect(JrcServiceDesk::Unit.count).to eq(original_units)
  end

  it 'denies cross-account and cross-unit assignment, without writing history' do
    target = create(:account_user, account: sd_account, role: :agent)
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: target)
    foreign = create(:account_user, account: sd_foreign_account, role: :agent)
    [target.id, foreign.id].each do |id|
      post "#{base}/tickets/#{row.id}/assign", headers: headers, as: :json,
        params: { assignment: { assignee_account_user_id: id }, expected_lock_version: row.lock_version }
      denied!
      expect(row.reload.assignee_membership_id).to be_nil
    end
    expect(row.ticket_events.count).to eq(0)
  end

  it 'denies a queue/priority from another unit and refuses a native contact from another Account' do
    other_queue = create(:jrc_sd_queue, unit: sd_other_unit)
    other_priority = create(:jrc_sd_priority, unit: sd_other_unit)
    post "#{base}/tickets/#{row.id}/assign", headers: headers, as: :json,
      params: { assignment: { queue_id: other_queue.id }, expected_lock_version: row.lock_version }
    denied!
    patch "#{base}/tickets/#{row.id}", headers: headers, as: :json,
      params: { ticket: { priority_id: other_priority.id }, expected_lock_version: row.lock_version }
    denied!
    post "#{base}/tickets", headers: headers.merge('Idempotency-Key' => 'bad-contact'), as: :json,
      params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(requester_id: create(:contact, account: sd_foreign_account).id) }
    denied!
  end

  %w[account_id operator_company_id unit_id created_by_membership_id lock_version status_id].each do |field|
    it "rejects spoofed #{field} in a generic edit payload" do
      patch "#{base}/tickets/#{row.id}", headers: headers, as: :json,
        params: { ticket: { title: 'Must not persist', field => 999 }, expected_lock_version: row.lock_version }
      denied!
      expect(row.reload.title).to eq('Test ticket')
    end
  end

  [{ unit_id: '01' }, { unit_id: ['1'] }, { page: '0' }, { per_page: '101' }, { sort: 'id; DROP TABLE' }, { account_id: '2' }].each do |params|
    it "rejects manipulated list parameters #{params.inspect}" do
      get "#{base}/tickets", headers: headers, params: params
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)).not_to have_key('items')
    end
  end

  it 'cannot read a note using the wrong ticket parent' do
    other = sd_ticket(title: 'Other same-unit ticket')
    note = create(:jrc_sd_note, ticket: other)
    get "#{base}/tickets/#{row.id}/notes/#{note.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'requires native conversation visibility in addition to Service Desk access' do
    conversation = create(:conversation, account: sd_account)
    expect(ConversationPolicy.new(sd_context, conversation).show?).to be(false)
    post "#{base}/tickets/#{row.id}/conversations", headers: headers, as: :json, params: { conversation_id: conversation.id }
    denied!
    expect(row.ticket_conversations.count).to eq(0)
  end

  it 'does not derive unit access from team membership' do
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    hidden = create(:jrc_sd_ticket, unit: sd_other_unit, team: team)
    get "#{base}/tickets/#{hidden.id}", headers: headers
    denied!
  end
end
