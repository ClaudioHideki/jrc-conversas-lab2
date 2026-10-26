# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk structural context authorization', type: :request do
  include_context 'JRC Service Desk domain'

  let(:root) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:errors) { [] }
  let(:delegated_permissions) do
    %w[module_view structure_view lookups_view settings_view categories_manage]
  end

  before do
    allow_any_instance_of(Api::V1::Accounts::JrcServiceDesk::StructureController)
      .to receive(:log_handled_error).and_wrap_original do |original, error|
        errors << error
        original.call(error)
      end
  end

  it 'returns the authenticated native Account context to an authorized administrator without creating an operational grant' do
    sd_as_admin!
    sd_membership.update!(active: false)
    before = [User.count, AccountUser.count, JrcServiceDesk::UnitMembership.count, sd_membership.reload.attributes]

    get "#{root}/structure/context", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body).to include('account_id' => sd_account.id.to_s, 'user_id' => sd_user.id.to_s,
                                           'account_user_id' => sd_account_user.id.to_s, 'available' => true,
                                           'can_manage_auto_assignment' => true)
    expect(response.parsed_body.fetch('capabilities').keys).to match_array(JrcServiceDesk::StructureContract::RESOURCES)
    expect([User.count, AccountUser.count, JrcServiceDesk::UnitMembership.count, sd_membership.reload.attributes]).to eq(before)
    expect(errors).to be_empty
  end

  it 'denies an ordinary operational agent with a concrete Account policy error and does not change permissions' do
    before = [sd_account_user.reload.attributes, sd_membership.reload.attributes]

    get "#{root}/structure/context", headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq('code' => 'forbidden', 'error' => 'Você não tem permissão para administrar a estrutura.')
    denied = errors.sole
    expect(denied.class.name).to eq('Pundit::NotAuthorizedError')
    expect(denied.record).to eq(sd_account)
    expect(denied.query).to eq(:context?)
    expect(denied.policy.class.name).to eq('JrcServiceDesk::StructurePolicy')
    expect(denied.message).not_to include('NilClass')
    expect([sd_account_user.reload.attributes, sd_membership.reload.attributes]).to eq(before)
  end

  it 'rechecks an administrator custom role without replacing a missing capability with global access' do
    role = create(:custom_role, account: sd_account, permissions: delegated_permissions.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(role: :administrator, custom_role: role)
    get "#{root}/structure/context", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('can_manage_auto_assignment')).to be(false)

    role.update!(permissions: %w[jrc_service_desk_module_view jrc_service_desk_settings_view])
    get "#{root}/structure/context", headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(errors.sole.record).to eq(sd_account)
    expect(errors.sole.query).to eq(:context?)
    expect(sd_account_user.reload).to have_attributes(role: 'administrator', custom_role_id: role.id)
    expect(role.reload.permissions).to eq(%w[jrc_service_desk_module_view jrc_service_desk_settings_view])
  end

  it 'does not substitute a SuperAdmin identity for an authorized client structure profile' do
    staff = create(:super_admin, confirmed_at: Time.current)
    staff_member = create(:account_user, account: sd_account, user: staff, role: :administrator)

    get "#{root}/structure/context", headers: staff.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
    expect(errors.sole.record).to eq(sd_account)
    expect(errors.sole.query).to eq(:context?)
    expect(staff_member.reload.role).to eq('administrator')
    expect(JrcServiceDesk::UnitMembership.where(account_user: staff_member)).not_to exist
  end

  it 'does not turn an authorized structural context into another unit or Account operational grant' do
    role = create(:custom_role, account: sd_account, permissions: delegated_permissions.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(role: :administrator, custom_role: role)
    other_id = sd_other_unit.id
    foreign_id = sd_foreign_account.id

    get "#{root}/structure/context", params: { unit_id: other_id, account_id: foreign_id,
                                               operator_company_id: sd_foreign_operator.id }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('account_id')).to eq(sd_account.id.to_s)
    get "#{root}/configuration/categories", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    get "#{root}/configuration/categories", params: { unit_id: other_id }, headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{foreign_id}/jrc_service_desk/structure/context", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq('code' => 'forbidden', 'error' => 'Você não tem permissão para administrar a estrutura.')
    expect(JrcServiceDesk::UnitMembership.where(account_user: sd_account_user, unit_id: [other_id, sd_foreign_unit.id])).not_to exist
  end

  it 'rejects an unauthenticated request and a disabled Account feature without returning structural data' do
    get "#{root}/structure/context"
    expect(response).to have_http_status(:unauthorized)

    sd_as_admin!
    sd_account.disable_features!('jrc_service_desk')
    get "#{root}/structure/context", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to be_blank
  end
end
