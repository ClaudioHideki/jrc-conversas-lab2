# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Accounts::JrcServiceDesk::BaseController, type: :controller do
  include Devise::Test::ControllerHelpers

  # This anonymous action and route exist only inside the test process.
  controller(described_class) do
    def index
      policy_scope(Current.account.contacts, policy_scope_class: ::JrcServiceDesk::BasePolicy::Scope)
      head :no_content
    end
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    @request.env['devise.mapping'] = Devise.mappings[:user]
    sign_in user
    user.create_new_auth_token.each { |header, value| @request.headers[header] = value }
  end

  it 'inherits native authentication and Account resolution' do
    expect(described_class.superclass).to eq(Api::V1::Accounts::BaseController)
  end

  it 'blocks the test action while the Service Desk flag is disabled' do
    account.disable_features!('jrc_service_desk')
    get :index, params: { account_id: account.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not let the enabled flag replace explicit authorization' do
    account.enable_features!('jrc_service_desk')
    expect { get :index, params: { account_id: account.id } }.to raise_error(Pundit::AuthorizationNotPerformedError)
  end

  it 'retains the native rejection of an account without membership' do
    other_account = create(:account)
    other_account.enable_features!('jrc_service_desk')
    get :index, params: { account_id: other_account.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not allow unauthenticated requests' do
    sign_out user
    %w[access-token token-type client expiry uid Authorization].each { |header| @request.headers[header] = nil }
    get :index, params: { account_id: account.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not expose its guard as a public controller action' do
    expect(described_class.action_methods).not_to include('ensure_service_desk_available!', 'service_desk_access_context')
  end

  it 'requires explicit policy scope verification for index actions' do
    callbacks = described_class._process_action_callbacks.select { |callback| callback.kind == :after }.map(&:filter)
    expect(callbacks).to include(:verify_authorized, :verify_policy_scoped)
  end
end
