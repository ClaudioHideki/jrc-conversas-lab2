# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP6-D01 human initialization in native Super Admin', type: :request do
  let(:account) { create(:account) }
  let(:staff) { create(:super_admin) }
  let(:target) { create(:account_user, account: account, role: :administrator) }
  let(:path) { "/super_admin/accounts/#{account.id}/service-desk-initialization" }
  let(:payload) { { request_key: 'manual-ui-request', initialization: { operator: { name: 'Explicit operator', code: 'explicit', active: 'true' },
    unit: { name: 'Explicit unit', code: 'explicit', active: 'true' }, account_user_id: target.id.to_s, confirmed: 'confirmed', reason: 'CHG-42' } } }
  before do
    account.enable_features!('jrc_service_desk')
    sign_in staff, scope: :super_admin
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with(JrcServiceDesk::InitializerAuthority::CONFIG_KEY, '').and_return(staff.id.to_s)
  end

  it 'GET has no grant side effects and a manual POST redirects to an independent receipt read' do
    get path
    expect(response).to have_http_status(:ok)
    expect(JrcServiceDesk::UnitMembership.where(account_id: account.id)).to be_empty
    post path, params: payload
    expect(response).to have_http_status(:see_other)
    receipt_path = response.location
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(JrcServiceDesk::UnitMembership.where(account_id: account.id).count).to eq(1)
    get receipt_path
    expect(JrcServiceDesk::UnitMembership.where(account_id: account.id).count).to eq(1)
    expect(AccountUser.where(account_id: account.id, user_id: staff.id)).to be_empty
  end

  it 'blocks removal of designation and never turns the feature on' do
    allow(ENV).to receive(:fetch).with(JrcServiceDesk::InitializerAuthority::CONFIG_KEY, '').and_return('')
    get path
    expect(response).to have_http_status(:forbidden)
    account.disable_features!('jrc_service_desk')
    post path, params: payload
    expect(account.reload.feature_enabled?('jrc_service_desk')).to be(false)
    expect(JrcServiceDesk::UnitMembership.where(account_id: account.id)).to be_empty
  end

  it 'preserves the native Super Admin account navigation with the nested initialization routes' do
    get super_admin_accounts_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(super_admin_account_path(account))
  end

  it 'requires CSRF for the native browser POST when protection is enabled' do
    previous = ActionController::Base.allow_forgery_protection
    previous_exceptions = Rails.application.env_config['action_dispatch.show_exceptions']
    begin
      ActionController::Base.allow_forgery_protection = true
      Rails.application.env_config['action_dispatch.show_exceptions'] = :all
      expect { post path, params: payload }.not_to change(JrcServiceDesk::UnitMembership, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    ensure
      ActionController::Base.allow_forgery_protection = previous
      Rails.application.env_config['action_dispatch.show_exceptions'] = previous_exceptions
    end
  end
  it 'rejects a malformed nested structural form without writing records' do
    expect { post path, params: { request_key: 'malformed', initialization: { operator: 'not-an-object' } } }
      .not_to change(JrcServiceDesk::OperatorCompany, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

end
