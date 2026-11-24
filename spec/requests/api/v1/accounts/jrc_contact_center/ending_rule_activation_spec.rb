# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit prospective ending automation activation through the native API', type: :request do
  include_context 'with native ending rule configuration'

  let(:headers) { actor.create_new_auth_token }
  let(:request_key) { SecureRandom.uuid }

  before { configure_native_ending_rule(rule_input.merge('execution_mode' => 'automatic')) }

  def activation_path
    "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules/activate"
  end

  def activation_document
    { rule_code: 'SYNTHETIC_RULE', request_key: request_key, expected_revision: policy.revision }
  end

  def request_activation(document = activation_document, request_headers = headers)
    post activation_path, headers: request_headers, as: :json, params: document
  end

  it 'records explicit current-version readiness without executing a destination or publishing configuration' do
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    request_activation
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    receipt = JrcContactCenter::EndingActionReadiness.where(account: account).sole
    expect(response.parsed_body.fetch('item')).to include('id' => receipt.id.to_s, 'rule_code' => 'SYNTHETIC_RULE', 'prospective_only' => true)
    expect(response.parsed_body.fetch('reviewed_revision')).to eq(policy.revision)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(receipt.actor_account_user_id).to eq(member.id)
  end

  it 'acknowledges the same exact request key without adding a second readiness or changing versions' do
    document = activation_document
    request_activation(document)
    first = response.parsed_body
    request_activation(document)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a revision changed after review without silently activating its replacement' do
    document = activation_document
    configure_native_ending_rule(rule_input.merge('name' => 'SYNTHETIC revised', 'execution_mode' => 'automatic'))
    request_activation(document)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'revalidates a configuration permission revoked before the actual request' do
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    member.update!(custom_role: role)
    request_activation
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
  end

  it 'preserves the native global-configuration coverage restriction after a unit-only restriction' do
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: business, active: true, structure_managed: true)
    request_activation
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
  end

  it 'does not accept a caller-supplied account, actor or unit as activation authority' do
    request_activation(activation_document.merge(account_id: account.id, user_id: actor.id, unit_id: unit.id))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'requires a bounded valid activation key without changing business state' do
    request_activation(activation_document.merge(request_key: 'SYNTHETIC invalid key'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_ending_activation_request')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'revalidates the actual native destination capability at activation time' do
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_projects_project_view])
    member.update!(custom_role: role)
    request_activation
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects an inactive rule instead of treating the saved configuration as activation' do
    configure_native_ending_rule(rule_input.merge('active' => false, 'execution_mode' => 'automatic'))
    request_activation
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('ending_action_not_ready')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects credentials from another account without leaking the private destination' do
    other = create(:account)
    person = create(:user, :contact_center_eligible, account: other, role: :administrator)
    request_activation(activation_document, person.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
  end

  it 'keeps the rule identity and request key filtered in actual controller instrumentation' do
    parameters = []
    subscriber = lambda do |*, payload|
      parameters << payload.fetch(:params).to_json if payload[:controller] == 'Api::V1::Accounts::JrcContactCenter::EndingRulesController'
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'start_processing.action_controller') { request_activation }
    expect(response).to have_http_status(:ok)
    expect(parameters).not_to be_empty
    expect(parameters.join).to include('[FILTERED]')
    expect(parameters.join).not_to include('SYNTHETIC_RULE', request_key, 'SYNTHETIC_PRIVATE_TEMPLATE_7f19')
  end

  it 'reads an empty persisted state through the authenticated route without implicitly activating it' do
    get "#{activation_path.delete_suffix('/activate')}/readiness", headers: headers,
                                                                   params: { rule_code: 'SYNTHETIC_RULE', expected_revision: policy.revision }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('last_review', 'applicable_review')).to eq([nil, nil])
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'reloads the actual stored review after activation with no private template or duplicate write' do
    request_activation
    saved = response.parsed_body.fetch('item')
    get "#{activation_path.delete_suffix('/activate')}/readiness", headers: headers,
                                                                   params: { rule_code: 'SYNTHETIC_RULE', expected_revision: policy.revision }
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.parsed_body.fetch('applicable_review')).to eq(saved)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'actor_user_id', 'request_key')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
