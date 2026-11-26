# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Explicit CRM ending configuration through the native private rule API', type: :request do
  include_context 'with native ending rule configuration'

  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules" }
  let(:crm_rule) do
    rule_input.merge('destination_schema_version' => 2, 'execution_mode' => 'automatic',
                     'actions' => [{ 'kind' => 'crm', 'parameters' => {} }])
  end

  before do
    account.enable_features!('jrc_crm')
    member.update!(crm_enabled: true)
  end

  def save_crm_rule(input = crm_rule)
    account.reload
    post path, headers: headers, as: :json, params: { private_rule: input, expected_revision: policy.revision }
  end

  it 'saves an explicitly new native CRM definition without creating a customer, Lead, Activity or execution intent' do
    contacts = account.contacts.count
    save_crm_rule
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('destination_schema_version' => 2, 'actions' => crm_rule.fetch('actions'))
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole.fetch('actions')).to eq(crm_rule.fetch('actions'))
    native_counts = [account.contacts.count, account.jrc_crm_leads.count, account.jrc_crm_activities.count,
                     JrcContactCenter::EndingDestinationAttempt.where(account: account).count, JrcProjects::Task.where(account: account).count]
    expect(native_counts).to eq([contacts, 0, 0, 0, 0])
  end

  it 'does not silently convert a legacy project-only request into the new destination grammar' do
    save_crm_rule(crm_rule.except('destination_schema_version'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'preserves an old immutable project definition exactly while adding a separately reviewed CRM rule' do
    configure_native_ending_rule
    previous = JrcContactCenter::EndingActionVersion.where(account: account).sole
    original = previous.private_definition.deep_dup
    save_crm_rule(crm_rule.merge('code' => 'SYNTHETIC_EXPLICIT_CRM'))
    expect(response).to have_http_status(:ok)
    expect(previous.reload.private_definition).to eq(original)
    get path, headers: headers
    rows = response.parsed_body.fetch('items')
    expect(rows.find { |row| row.fetch('code') == rule_input.fetch('code') }).not_to have_key('destination_schema_version')
    expect(rows.find { |row| row.fetch('code') == 'SYNTHETIC_EXPLICIT_CRM' }.fetch('destination_schema_version')).to eq(2)
  end

  it 'normalizes an explicit native activity type and bounded private text without accepting owner or customer IDs' do
    action = { 'kind' => 'crm', 'parameters' => { 'operation' => 'create_activity', 'parameters' => {
      'activity_type' => 'call', 'title' => 'SYNTHETIC current native activity', 'description' => 'SYNTHETIC reviewed private result'
    } } }
    save_crm_rule(crm_rule.merge('actions' => [action]))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('actions')).to eq([action])
    expect(account.jrc_crm_activities).to be_empty
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  it 'rejects an activity type outside the native CRM catalogue rather than inventing a new operation' do
    action = { 'kind' => 'crm', 'parameters' => { 'operation' => 'create_activity', 'parameters' => {
      'activity_type' => 'SYNTHETIC_UNKNOWN', 'title' => 'SYNTHETIC rejected'
    } } }
    save_crm_rule(crm_rule.merge('actions' => [action]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'denies saving and hides the existing CRM template after native account CRM enablement is withdrawn' do
    save_crm_rule
    expect(response).to have_http_status(:ok)
    account.disable_features!('jrc_crm')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    save_crm_rule(crm_rule.merge('name' => 'SYNTHETIC denied current feature'))
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'does not derive CRM permission from native Call Center configure access or administrator role' do
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    member.update!(custom_role: role, crm_enabled: true)
    save_crm_rule
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(account.jrc_crm_leads).to be_empty
  end

  it 'rechecks native nonadministrator CRM enablement even when configuration and CRM permissions remain' do
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_crm])
    member.update!(role: :agent, custom_role: role, crm_enabled: false)
    save_crm_rule
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'rejects caller-selected customer and actor parameters instead of treating them as authority' do
    save_crm_rule(crm_rule.merge('actions' => [{ 'kind' => 'crm', 'parameters' => { 'contact_id' => '1', 'owner_id' => actor.id.to_s } }]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(account.jrc_crm_leads).to be_empty
  end

  it 'requires an exact integer opt-in and does not coerce a string destination schema' do
    save_crm_rule(crm_rule.merge('destination_schema_version' => '2'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'edits an existing CRM rule through a new immutable version without changing its earlier snapshot' do
    save_crm_rule
    expect(response).to have_http_status(:ok)
    previous = JrcContactCenter::EndingActionVersion.where(account: account).sole
    snapshot = previous.private_definition.deep_dup
    save_crm_rule(crm_rule.merge('name' => 'SYNTHETIC reviewed CRM edit'))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('name')).to eq('SYNTHETIC reviewed CRM edit')
    expect(previous.reload.private_definition).to eq(snapshot)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  it 'deactivates an existing authorized CRM rule without removing its immutable prior definition' do
    save_crm_rule
    expect(response).to have_http_status(:ok)
    previous = JrcContactCenter::EndingActionVersion.where(account: account).sole
    save_crm_rule(crm_rule.merge('active' => false))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('active')).to be false
    expect(previous.reload.definition.fetch('entries').sole.fetch('active')).to be true
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
  end

  it 'does not overwrite a now-invisible CRM rule by replacing it with an accessible Project action' do
    save_crm_rule
    expect(response).to have_http_status(:ok)
    account.disable_features!('jrc_crm')
    save_crm_rule(rule_input)
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account)).to be_empty
  end

  it 'keeps Service Desk configuration blocked until all native mapping and reference checks are available' do
    parameters = {
      'unit_id' => '1', 'service_id' => nil, 'attributes' => { 'title' => 'SYNTHETIC unavailable' }
    }
    action = { 'kind' => 'service_desk', 'parameters' => parameters }
    save_crm_rule(crm_rule.merge('actions' => [action]))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end
end
