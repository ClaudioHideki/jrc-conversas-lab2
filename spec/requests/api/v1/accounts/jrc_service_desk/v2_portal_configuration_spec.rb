# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk real portal configuration choices', type: :request do
  include_context 'JRC Service Desk domain'
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/configuration/portal_options" }
  let(:headers) { sd_user.create_new_auth_token }

  it 'requires catalogue management and never grants an ordinary agent publication authority' do
    get path, params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'offers real scoped native widgets and authorized execution memberships without exposing widget secrets' do
    sd_as_admin!
    widget = create(:channel_widget, account: sd_account)
    foreign_widget = create(:channel_widget, account: sd_foreign_account)
    agent = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: agent)
    get path, params: { unit_id: sd_unit.id, inbox_id: widget.inbox.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['inboxes'].map { |row| row['id'] }).to include(widget.inbox.id.to_s)
    expect(response.parsed_body['inboxes'].map { |row| row['id'] }).not_to include(foreign_widget.inbox.id.to_s)
    expect(response.parsed_body['execution_memberships'].map { |row| row['id'] }).to include(sd_membership.id.to_s)
    expect(response.parsed_body['execution_memberships'].map { |row| row['id'] }).not_to include(grant.id.to_s)
    expect(response.body).not_to include(widget.website_token, 'hmac', 'token', 'secret', 'account_user_id')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'recalculates eligibility after native channel access or operational membership is revoked' do
    sd_as_admin!
    widget = create(:channel_widget, account: sd_account)
    agent = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: agent)
    native_access = create(:inbox_member, inbox: widget.inbox, user: agent.user)
    get path, params: { unit_id: sd_unit.id, inbox_id: widget.inbox.id }, headers: headers
    expect(response.parsed_body['execution_memberships'].map { |row| row['id'] }).to include(grant.id.to_s)
    native_access.destroy!
    get path, params: { unit_id: sd_unit.id, inbox_id: widget.inbox.id }, headers: headers
    expect(response.parsed_body['execution_memberships'].map { |row| row['id'] }).not_to include(grant.id.to_s)
    sd_membership.update!(active: false)
    get path, params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects another unit and foreign widget without returning choices' do
    sd_as_admin!
    get path, params: { unit_id: sd_other_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    foreign = create(:channel_widget, account: sd_foreign_account)
    get path, params: { unit_id: sd_unit.id, inbox_id: foreign.inbox.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
