# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native per-rule ending configuration within existing corporate coverage', type: :request do
  include_context 'with native ending rule configuration'

  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules" }
  let(:second_business) do
    JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer, code: 'SYNTHETIC_SCOPED_EDITOR_OTHER',
                                 name: 'SYNTHETIC other rule source', active: true)
  end
  let(:second_unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC_SCOPED_EDITOR_OTHER', name: 'SYNTHETIC other operational source', kind: 'sac',
                                   settings: { 'issuer_company_id' => issuer.id.to_s, 'business_unit_id' => second_business.id.to_s })
  end
  let(:second_queue) do
    JrcContactCenter::Queue.create!(account: account, unit: second_unit, code: 'SYNTHETIC_SCOPED_EDITOR_OTHER',
                                    name: 'SYNTHETIC other private queue', service_kind: 'voice', strategy: 'ring_all')
  end
  let(:second_scope) do
    JrcContactCenter::EndingActionQueueScope.where(account: account, source_queue_id: second_queue.id).order(:revision).last!
  end
  let(:second_rule) do
    row = rule_input.deep_dup.merge('code' => 'SYNTHETIC_OTHER_RULE', 'queue_id' => second_queue.id.to_s,
                                    'scope_revision' => second_scope.integrity_sha256)
    row.fetch('actions').first.fetch('parameters').fetch('attributes')['title'] = 'SYNTHETIC_OTHER_UNIT_PRIVATE_TEMPLATE'
    row
  end
  let(:catalogue_manager) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:catalogue_member) { account.account_users.find_by!(user: catalogue_manager) }

  before do
    second_queue
    JrcServiceDesk::NativeExecutionContext.with(user: actor, account: account, account_user: member) do
      policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_required_queue_ids: [queue.id.to_s, second_queue.id.to_s],
                                                    voice_reason_confirmation: true, expected_revision: policy.revision)
    end
    configure_native_ending_rule
    configure_native_ending_rule(second_rule)
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: business, active: true, structure_managed: true)
  end

  it 'lists only the authorized source and a bounded shared reason context without global policy fields' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.fetch('items').pluck('code')).to eq(['SYNTHETIC_RULE'])
    expect(body.fetch('meta').fetch('total')).to eq(1)
    context = body.fetch('editor_context')
    expect(context.keys.sort).to eq(%w[destination_options id revision voice_reason_catalog])
    expect(context.values_at('id', 'revision')).to eq([account.id.to_s, body.fetch('revision')])
    expect(context.fetch('voice_reason_catalog').fetch('entries').sole.keys.sort).to eq(%w[active code name])
    expect(response.body).not_to include('SYNTHETIC_OTHER_UNIT_PRIVATE_TEMPLATE', 'SYNTHETIC other private queue', 'required_queue_ids')
  end

  it 'preserves public operational ACW limits while hiding global configuration and denying its writer' do
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy"
    previous = policy.revision
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').keys.sort).to eq(%w[enabled id limits require_reason require_result revision voice_required])
    expect(response.body).not_to include('SYNTHETIC_OTHER_UNIT_PRIVATE_TEMPLATE', 'voice_reason_catalog', 'voice_form_bindings', 'voice_rules')
    patch endpoint, headers: headers, params: { limits: { voice: 120, whatsapp: 120 }, expected_revision: previous }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(policy.revision).to eq(previous)
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP', active: true)).to be_empty
  end

  it 'returns the owned source context while denying a real queue in another business unit' do
    get "#{path}/source_context", headers: headers, params: { queue_id: queue.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('id')).to eq(queue.id.to_s)
    get "#{path}/source_context", headers: headers, params: { queue_id: second_queue.id.to_s }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('SYNTHETIC other private queue')
  end

  it 'writes one owned rule using the existing audited catalogue while preserving the unseen rule exactly' do
    original = JrcContactCenter::EndingActions::Catalogue.new(account: account).call.fetch('entries')
    previous = original.find { |row| row['code'] == second_rule['code'] }
    input = rule_input.merge('name' => 'SYNTHETIC owned reviewed edit')
    post path, headers: headers, as: :json, params: { private_rule: input, expected_revision: policy.revision }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('name')).to eq('SYNTHETIC owned reviewed edit')
    current = JrcContactCenter::EndingActions::Catalogue.new(account: account.reload).call.fetch('entries')
    expect(current.find { |row| row['code'] == second_rule['code'] }).to eq(previous)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(3)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not steal an unseen rule by replacing its source and private parameters with an accessible rule' do
    previous = ending_rule_write_counts
    input = rule_input.merge('code' => second_rule.fetch('code'))
    post path, headers: headers, as: :json, params: { private_rule: input, expected_revision: policy.revision }
    expect(response).to have_http_status(:unauthorized)
    expect(ending_rule_write_counts).to eq(previous)
    expect(response.body).not_to include('SYNTHETIC_OTHER_UNIT_PRIVATE_TEMPLATE')
  end

  it 'revalidates native configuration permission after an authorized scoped read' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view]))
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    post path, headers: headers, as: :json, params: { private_rule: rule_input, expected_revision: policy.revision }
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
    expect(response.body).not_to include('SYNTHETIC_OTHER_UNIT_PRIVATE_TEMPLATE')
  end

  it 'denies a retained native profile when its actual corporate coverage is revoked' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, active: true).find_each { |row| row.update!(active: false) }
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
  end

  it 'does not turn a supplied account or user identifier into cross-account authority' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/jrc_contact_center/acw_policy/ending_rules", headers: headers
    expect(response).to have_http_status(:unauthorized)
    input = rule_input.merge('account_id' => other.id, 'user_id' => actor.id, 'unit_id' => second_unit.id)
    post path, headers: headers, as: :json, params: { private_rule: input, expected_revision: policy.revision }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
  end

  it 'does not announce an unregistered source as ready or opt it in on behalf of a scoped configurator' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: catalogue_manager, scope: 'GROUP', active: true, structure_managed: true)
    JrcServiceDesk::NativeExecutionContext.with(user: catalogue_manager, account: account, account_user: catalogue_member) do
      policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_required_queue_ids: [second_queue.id.to_s],
                                                    voice_reason_confirmation: true, expected_revision: policy.revision)
    end
    get "#{path}/source_context", headers: headers, params: { queue_id: queue.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('registered_reason_required' => false, 'configuration_available' => false)
    catalogue = JrcContactCenter::AcwEndingReasons.new(account: account.reload).call
    expect(catalogue.fetch('required_queue_ids')).to eq([second_queue.id.to_s])
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP', active: true)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
