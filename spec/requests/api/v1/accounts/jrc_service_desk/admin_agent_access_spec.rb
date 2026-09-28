# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk administrative and operational profiles', type: :request do
  include_context 'JRC Service Desk domain'

  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:admin_permissions) do
    %w[module_view lookups_view settings_view categories_manage priorities_manage statuses_manage queues_manage services_manage
       lifecycle_policies_manage structure_view unit_memberships_manage units_manage operator_companies_manage]
  end
  let(:agent_permissions) { %w[module_view lookups_view tickets_view tickets_edit tickets_assign] }
  let(:role) { create(:custom_role, account: sd_account, permissions: []) }

  before { sd_account_user.update!(role: :administrator, custom_role: role) }

  def delegate_permissions(keys)
    role.update!(permissions: keys.map { |key| "jrc_service_desk_#{key}" })
  end

  it 'allows configuration without ticket capabilities and denies operational reads and writes' do
    row = sd_ticket
    delegate_permissions(admin_permissions)
    get "#{root}/configuration/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/ui_context", headers: headers
    expect(response.parsed_body.dig('capabilities', 'settings', 'index')).to be(true)
    expect(response.parsed_body.dig('capabilities', 'tickets', 'index')).to be(false)
    get "#{root}/tickets", headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{root}/tickets/#{row.id}", headers: headers
    expect(response.status).to be_in([403, 404])
    patch "#{root}/tickets/#{row.id}", params: { ticket: { title: 'Denied change' } }, headers: headers, as: :json
    expect(response.status).to be_in([403, 404])
    expect(row.reload.title).not_to eq('Denied change')
  end

  it 'allows structural administration without membership but never configuration or tickets outside scope' do
    delegate_permissions(admin_permissions)
    sd_membership.update!(active: false)
    get "#{root}/structure/members", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/tickets", headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{root}/configuration/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'allows an agent in scope but rejects administrative API reads and writes' do
    row = sd_ticket
    sd_account_user.update!(role: :agent)
    delegate_permissions(agent_permissions)
    get "#{root}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/ui_context", headers: headers
    expect(response.parsed_body.dig('capabilities', 'settings', 'index')).to be(false)
    get "#{root}/configuration/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
    post "#{root}/configuration/categories", params: {
      unit_id: sd_unit.id, record: { name: 'Forbidden', code: 'forbidden', active: true }
    }, headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:forbidden)
    get "#{root}/structure/context", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'allows both explicitly delegated profiles only within granted units' do
    row = sd_ticket
    delegate_permissions(admin_permissions + agent_permissions)
    get "#{root}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/configuration/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/structure/context", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/configuration/categories", params: { unit_id: sd_other_unit.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    other_unit_ticket = create(:jrc_sd_ticket, unit: sd_other_unit)
    get "#{root}/tickets/#{other_unit_ticket.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    foreign_ticket = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    get "#{root}/tickets/#{foreign_ticket.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk/structure/context", headers: headers
    expect(response.status).to be_in([401, 403, 404])
  end

  it 'denies absent capabilities, inactive membership and disabled feature independently' do
    get "#{root}/ui_context", headers: headers
    expect(response).to have_http_status(:forbidden)
    delegate_permissions(agent_permissions)
    sd_membership.update!(active: false)
    get "#{root}/ui_context", headers: headers
    expect(response).to have_http_status(:forbidden)
    sd_membership.update!(active: true)
    delegate_permissions(admin_permissions + agent_permissions)
    sd_account.disable_features!('jrc_service_desk')
    get "#{root}/ui_context", headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{root}/structure/context", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end
