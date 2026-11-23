# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Ending automation configuration through the existing ACW policy', type: :request do
  include_context 'with native ending rule configuration'

  let(:headers) { actor.create_new_auth_token }

  def ending_rules_path
    "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules"
  end

  def create_ending_rule_document(rule = rule_input, revision: policy.revision)
    post ending_rules_path, headers: headers, as: :json, params: { private_rule: rule, expected_revision: revision }
  end

  it 'persists one explicit authorized rule through the actual API and returns the same private rule on reload' do
    create_ending_rule_document
    expect(response).to have_http_status(:ok)
    saved = response.parsed_body.fetch('item')
    expect(saved.fetch('actions').first.fetch('parameters').fetch('attributes').fetch('title')).to eq('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    expect(response.headers['Cache-Control']).to eq('no-store')
    get ending_rules_path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([saved])
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'keeps absent rule configuration empty without enabling a catalogue or destination' do
    get ending_rules_path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'persists an explicitly inactive empty draft without executing or silently choosing a destination' do
    create_ending_rule_document(rule_input.merge('active' => false, 'actions' => [], 'execution_mode' => 'agent_confirmation'))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('active' => false, 'actions' => [], 'execution_mode' => 'agent_confirmation')
    get ending_rules_path, headers: headers, params: { status: 'inactive' }
    expect(response.parsed_body.fetch('items').sole.fetch('actions')).to be_empty
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'paginates and filters authorized rules without changing their private templates' do
    3.times { |index| configure_native_ending_rule(rule_input.merge('code' => "SYNTHETIC_#{index}", 'name' => "SYNTHETIC rule #{index}")) }
    get ending_rules_path, headers: headers, params: { page: 2, per_page: 1, status: 'active', reason_code: 'SYNTHETIC_REASON' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('code')).to eq(['SYNTHETIC_1'])
    expect(response.parsed_body.fetch('meta')).to eq('page' => 2, 'per_page' => 1, 'total' => 3, 'pages' => 3)
    get ending_rules_path, headers: headers, params: { q: 'rule 2' }
    expect(response.parsed_body.fetch('items').pluck('code')).to eq(['SYNTHETIC_2'])
  end

  it 'returns a conflict on a stale native revision without overwriting the preceding rule' do
    revision = policy.revision
    configure_native_ending_rule
    before = ending_rule_write_counts
    create_ending_rule_document(rule_input.merge('name' => 'SYNTHETIC stale edit'), revision: revision)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'returns the current queue scope revision and rejects saving a scope changed since the form loaded' do
    get "#{ending_rules_path}/source_context", headers: headers, params: { queue_id: queue.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('scope_revision')).to eq(scope.integrity_sha256)
    input = rule_input.deep_dup
    unit.update!(settings: { 'issuer_company_id' => issuer.id })
    create_ending_rule_document(input)
    expect(response).to have_http_status(:conflict)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'rejects a revoked native configuration profile on both read and write without leaking a saved template' do
    configure_native_ending_rule
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    member.update!(custom_role: role)
    get ending_rules_path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    create_ending_rule_document
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'rejects another accounts queue context rather than accepting an account or unit identifier from the caller' do
    other = create(:account)
    foreign = JrcContactCenter::Unit.create!(account: other, code: 'SYNTHETIC_OTHER', name: 'SYNTHETIC other', kind: 'sac')
    foreign_queue = JrcContactCenter::Queue.create!(account: other, unit: foreign, code: 'SYNTHETIC_OTHER', name: 'SYNTHETIC other',
                                                    service_kind: 'voice', strategy: 'ring_all')
    get "#{ending_rules_path}/source_context", headers: headers, params: { queue_id: foreign_queue.id.to_s }
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'preserves null and false action entries for validation instead of silently dropping them in JSON parsing' do
    [nil, false].each do |malformed|
      input = rule_input.deep_dup
      input['actions'] << malformed
      create_ending_rule_document(input)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_ending_automation_rule')
    end
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'does not accept actor or account attributes as rule authority' do
    input = rule_input.merge('user_id' => actor.id, 'account_id' => account.id, 'unit_id' => unit.id)
    create_ending_rule_document(input)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'filters the private rule in the actual controller instrumentation without weakening the native log filter' do
    parameters = []
    subscriber = lambda do |*, payload|
      parameters << payload.fetch(:params).to_json if payload[:controller] == 'Api::V1::Accounts::JrcContactCenter::EndingRulesController'
    end
    ActiveSupport::Notifications.subscribed(subscriber, 'start_processing.action_controller') { create_ending_rule_document }
    expect(response).to have_http_status(:ok)
    expect(parameters).not_to be_empty
    expect(parameters.join).to include('[FILTERED]')
    expect(parameters.join).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'SYNTHETIC_RULE')
  end

  it 'does not include a private destination or its count after the configurator loses native project access' do
    configure_native_ending_rule
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { owner_id: other.id, visibility: 'private', lock_version: project.reload.lock_version },
                                       correlation_id: 'SYNTHETIC_PRIVATE_REVOKE')
    project.project_members.find_by!(account: account, user: actor).destroy!
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure
                                                                  jrc_projects_project_view jrc_projects_task_create])
    member.update!(custom_role: role)
    expect(JrcOperations::Access.projects(member)).not_to include(project)
    get ending_rules_path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'SYNTHETIC_RULE')
  end

  it 'rejects invalid pagination instead of silently treating it as an unrestricted request' do
    [0, -1, 'all', '01', '1.5', '1000001'].each do |page|
      get ending_rules_path, headers: headers, params: { page: page }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_ending_rule_filters')
    end
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'rejects disabled module access before returning a private template' do
    configure_native_ending_rule
    account.disable_features!('jrc_contact_center')
    get ending_rules_path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'rejects tenant-wide rule reads and writes after coverage is restricted to one business unit' do
    configure_native_ending_rule
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: business, active: true, structure_managed: true)
    get ending_rules_path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    create_ending_rule_document
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'does not overwrite an unseen private rule by replacing its destination with an accessible project' do
    configure_native_ending_rule
    person = create(:user, :contact_center_eligible, account: account, role: :administrator)
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { owner_id: person.id, visibility: 'private', lock_version: project.reload.lock_version },
                                       correlation_id: 'SYNTHETIC_PRIVATE_REVOKE')
    project.project_members.find_by!(account: account, user: actor).destroy!
    visible = JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'SYNTHETIC visible destination' },
                                               idempotency_key: SecureRandom.uuid)
    input = rule_input.deep_dup
    values = input.fetch('actions').first.fetch('parameters')
    values['project_id'] = visible.id.to_s
    values['attributes']['board_column_id'] = visible.board_columns.find_by!(status_key: 'backlog').id.to_s
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure
                                                                  jrc_projects_project_view jrc_projects_task_create])
    member.update!(custom_role: role)
    expect(JrcOperations::Access.projects(member)).to include(visible)
    expect(JrcOperations::Access.projects(member)).not_to include(project)
    create_ending_rule_document(input)
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).sole.definition.fetch('entries').first.fetch('actions')
             .first.fetch('parameters').fetch('project_id')).to eq(project.id.to_s)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'keeps the exact legacy definition when another rule explicitly selects an execution mode' do
    configure_native_ending_rule
    original = JrcContactCenter::EndingActionVersion.where(account: account).sole.definition
    input = rule_input.merge('code' => 'SYNTHETIC_EXPLICIT', 'execution_mode' => 'agent_confirmation')
    create_ending_rule_document(input)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('execution_mode')).to eq('agent_confirmation')
    expect(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).first.definition).to eq(original)
    get ending_rules_path, headers: headers, params: { rule_code: 'SYNTHETIC_RULE' }
    expect(response.parsed_body.fetch('items').sole).not_to have_key('execution_mode')
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(1)
  end

  it 'rejects an invalid explicit mode without silently selecting automatic execution' do
    [nil, false, '', 'administrator', {}].each do |mode|
      create_ending_rule_document(rule_input.merge('execution_mode' => mode))
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'permits an authorized deactivation after the destination closes but rejects reactivation against that closed destination' do
    configure_native_ending_rule
    project.update!(status: 'completed')
    create_ending_rule_document(rule_input.merge('active' => false, 'execution_mode' => 'automatic'))
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('active')).to be(false)
    before = ending_rule_write_counts
    create_ending_rule_document(rule_input.merge('execution_mode' => 'automatic'))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ending_rule_write_counts).to eq(before)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'filters by exact logical code without exposing another authorized rule during revision review' do
    configure_native_ending_rule
    configure_native_ending_rule(rule_input.merge('code' => 'SYNTHETIC_RULE_SUFFIX'))
    get ending_rules_path, headers: headers, params: { rule_code: 'SYNTHETIC_RULE' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('code')).to eq(['SYNTHETIC_RULE'])
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(1)
  end
end
