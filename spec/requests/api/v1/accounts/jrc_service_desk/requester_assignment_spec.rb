# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk requester phone and team assignment', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:team) { create(:team, account: sd_account) }

  it 'projects actual opening time separately from persistence time for detail and list' do
    row = sd_ticket(opened_at: 2.days.ago.change(usec: 0))
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    actual = response.parsed_body.fetch('ticket')
    expect(Time.iso8601(actual.fetch('opened_at'))).to eq(row.opened_at)
    expect(Time.iso8601(actual.fetch('created_at'))).not_to eq(row.opened_at)
    get "#{base}/tickets", headers: headers
    expect(response).to have_http_status(:ok)
    listed = response.parsed_body.fetch('items').find { |item| item['id'] == row.id.to_s }
    expect(Time.iso8601(listed.fetch('opened_at'))).to eq(row.opened_at)
  end

  it 'projects the native phone for authorized requester lookup and persisted ticket' do
    sd_contact.update!(phone_number: '+5511999990001')
    row = sd_ticket
    get "#{base}/requesters", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    values = response.parsed_body.fetch('items')
    expect(values.find { |item| item['id'] == sd_contact.id.to_s }['phone_number']).to eq(sd_contact.phone_number)
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response.parsed_body.dig('ticket', 'requester', 'phone_number')).to eq(sd_contact.phone_number)
  end

  it 'does not project a foreign contact phone through lookups or a foreign ticket' do
    foreign_contact = create(:contact, account: sd_foreign_account, phone_number: '+5511999990002')
    foreign_ticket = create(:jrc_sd_ticket, unit: sd_foreign_unit, requester: foreign_contact)
    get "#{base}/requesters", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(foreign_contact.phone_number)
    get "#{base}/tickets/#{foreign_ticket.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign_contact.phone_number)
  end

  it 'honors customer permission revocation for phone projection' do
    row = sd_ticket
    sd_account_user.update!(role: :agent, custom_role: create(:custom_role, account: sd_account,
      permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_lookups_view]))
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket', 'requester')).to be_nil
    get "#{base}/requesters", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'filters team members before pagination without granting unit access' do
    create(:team_member, team: team, user: sd_user)
    other_user = create(:user)
    other_account_user = create(:account_user, account: sd_account, user: other_user, role: :agent)
    create(:jrc_sd_membership, unit: sd_unit, account_user: other_account_user)
    unbound_user = create(:user)
    create(:account_user, account: sd_account, user: unbound_user, role: :agent)
    create(:team_member, team: team, user: unbound_user)
    get "#{base}/assignees", params: { unit_id: sd_unit.id, team_id: team.id, per_page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    expect(response.parsed_body.fetch('items').map { |item| item['account_user_id'] }).to eq([sd_account_user.id.to_s])
  end

  it 'rejects foreign teams and malformed team filters' do
    foreign_team = create(:team, account: sd_foreign_account)
    get "#{base}/assignees", params: { unit_id: sd_unit.id, team_id: foreign_team.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/assignees", params: { unit_id: sd_unit.id, team_id: '01' }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{base}/requesters", params: { unit_id: sd_unit.id, team_id: team.id }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
