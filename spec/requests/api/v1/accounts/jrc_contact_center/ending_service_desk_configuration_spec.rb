# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native Service Desk templates in the existing private ending rule API', type: :request do
  include_context 'with native ending rule configuration'
  include_context 'JRC Service Desk domain'

  let(:sd_account) { account }
  let(:sd_user) { actor }
  let(:sd_account_user) { member }
  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy/ending_rules" }
  let(:sd_parameters) do
    { 'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
      'attributes' => { 'title' => 'SYNTHETIC private ticket template', 'description' => 'SYNTHETIC reviewed description',
                        'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s } }
  end
  let(:sd_rule) do
    rule_input.merge('destination_schema_version' => 2, 'execution_mode' => 'agent_confirmation',
                     'actions' => [{ 'kind' => 'service_desk', 'parameters' => sd_parameters }])
  end

  before do
    # Explicit synthetic grants make operational membership revocation meaningful.
    # Native administrators without a custom role retain their native SD access.
    account.enable_features!('custom_roles')
    rights = %w[jrc_contact_center_view jrc_contact_center_configure jrc_service_desk_module_view jrc_service_desk_tickets_view
                jrc_service_desk_tickets_create jrc_service_desk_lookups_view jrc_service_desk_customers_view
                jrc_projects_project_view jrc_projects_project_create jrc_projects_task_create jrc_projects_task_view
                jrc_projects_task_assign jrc_projects_task_update jrc_projects_member_view]
    member.update!(custom_role: create(:custom_role, account: account, permissions: rights))
    sd_membership
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
    sd_rule
  end

  def save_service_desk_rule(input = sd_rule, revision: :current)
    account.reload
    expected = revision == :current ? policy.revision : revision
    post path, headers: headers, params: { private_rule: input, expected_revision: expected }, as: :json
  end

  it 'persists and reloads a reviewed native template without creating a Ticket, requester, event or execution' do
    counts = [account.contacts.count, JrcServiceDesk::UnitMembership.where(account: account).count]
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole.fetch('actions')).to eq(sd_rule.fetch('actions'))
    expect(response.parsed_body.fetch('destination_presentations').fetch(sd_rule.fetch('code')).fetch('service_desk')).to include(
      'unit' => { 'id' => sd_unit.id.to_s, 'name' => sd_unit.name },
      'status' => { 'id' => sd_status.id.to_s, 'name' => sd_status.name },
      'priority' => { 'id' => sd_priority.id.to_s, 'name' => sd_priority.name }
    )
    expect([account.contacts.count, JrcServiceDesk::UnitMembership.where(account: account).count]).to eq(counts)
    expect([JrcServiceDesk::Ticket.where(account: account).count, JrcServiceDesk::TicketEvent.where(account: account).count,
            JrcContactCenter::EndingDestinationAttempt.where(account: account).count]).to eq([0, 0, 0])
  end

  it 'stores a new immutable version on edit and preserves the earlier private snapshot' do
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    previous = JrcContactCenter::EndingActionVersion.where(account: account).sole
    original = previous.private_definition.deep_dup
    input = sd_rule.deep_dup
    input.fetch('actions').sole.fetch('parameters').fetch('attributes')['title'] = 'SYNTHETIC reviewed replacement'
    save_service_desk_rule(input)
    expect(response).to have_http_status(:ok)
    expect(previous.reload.private_definition).to eq(original)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'keeps an authorized historical status readable and permits deactivation without accepting an invalid new activation' do
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    old = JrcContactCenter::EndingActionVersion.where(account: account).sole
    snapshot = old.private_definition.deep_dup
    sd_status.update!(initial: false)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole.fetch('code')).to eq(sd_rule.fetch('code'))
    save_service_desk_rule(sd_rule.merge('active' => false))
    expect(response).to have_http_status(:ok)
    save_service_desk_rule
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(2)
    expect(old.reload.private_definition).to eq(snapshot)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'permits reviewing and correcting a stale required catalogue field without rewriting the previous version' do
    category = create(:jrc_sd_category, unit: sd_unit)
    input = sd_rule.deep_dup
    input.fetch('actions').sole.fetch('parameters').fetch('attributes')['category_id'] = category.id.to_s
    save_service_desk_rule(input)
    expect(response).to have_http_status(:ok)
    old = JrcContactCenter::EndingActionVersion.where(account: account).sole
    snapshot = old.private_definition.deep_dup
    category.update!(form_fields: [{ 'key' => 'review_reference', 'label' => 'SYNTHETIC review reference',
                                     'type' => 'text', 'required' => true }])
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole.fetch('code')).to eq(sd_rule.fetch('code'))
    save_service_desk_rule(input)
    expect(response).to have_http_status(:unprocessable_entity)
    input.fetch('actions').sole.fetch('parameters').fetch('attributes')['service_fields'] = { 'review_reference' => 'SYNTHETIC reviewed' }
    save_service_desk_rule(input)
    expect(response).to have_http_status(:ok)
    expect(old.reload.private_definition).to eq(snapshot)
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'requires current native Service Desk rights independently of the Call Center configure permission' do
    member.update!(custom_role: create(:custom_role, account: account,
                                       permissions: %w[jrc_contact_center_view jrc_contact_center_configure]))
    save_service_desk_rule
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'does not bypass native assignment rights through a service default queue omitted from caller parameters' do
    native_queue = create(:jrc_sd_queue, unit: sd_unit)
    service = JrcServiceDesk::Service.create!(account: account, unit: sd_unit, code: 'SYNTHETIC_DEFAULT_QUEUE',
                                              name: 'SYNTHETIC service assignment', active: true, default_queue: native_queue,
                                              form_fields: [], allowed_company_ids: [], allowed_contract_ids: [])
    input = sd_rule.deep_dup
    input.fetch('actions').sole.fetch('parameters')['service_id'] = service.id.to_s
    save_service_desk_rule(input)
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'withdraws the private existing template after native operational membership revocation' do
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    sd_membership.update!(active: false)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.body).not_to include(sd_parameters.fetch('attributes').fetch('title'))
  end

  it 'does not infer a native destination mapping from a supplied unit identifier' do
    business.update!(settings: business.settings.except('service_desk_unit_id'))
    save_service_desk_rule
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'denies another account unit without disclosing its label or creating a version' do
    input = sd_rule.deep_dup
    input.fetch('actions').sole.fetch('parameters')['unit_id'] = sd_foreign_unit.id.to_s
    save_service_desk_rule(input)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(sd_foreign_unit.name)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'rejects an inaccessible native reference even when its unit parameter is authorized' do
    input = sd_rule.deep_dup
    foreign = create(:jrc_sd_status, unit: sd_other_unit)
    input.fetch('actions').sole.fetch('parameters').fetch('attributes')['status_id'] = foreign.id.to_s
    save_service_desk_rule(input)
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
  end

  it 'rejects caller-selected requester or actor fields instead of treating them as source authority' do
    input = sd_rule.deep_dup
    input.fetch('actions').sole.fetch('parameters').fetch('attributes')['requester_id'] = actor.id.to_s
    save_service_desk_rule(input)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'preserves optimistic revision review and does not create a second version from stale input' do
    revision = policy.revision
    save_service_desk_rule(revision: revision)
    expect(response).to have_http_status(:ok)
    save_service_desk_rule(sd_rule.merge('name' => 'SYNTHETIC stale draft'), revision: revision)
    expect(response).to have_http_status(:conflict)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
  end

  it 'keeps a legacy Project rule immutable while adding a separately reviewed Service Desk definition' do
    configure_native_ending_rule
    previous = JrcContactCenter::EndingActionVersion.where(account: account).sole
    original = previous.private_definition.deep_dup
    save_service_desk_rule(sd_rule.merge('code' => 'SYNTHETIC_SERVICE_DESK'))
    expect(response).to have_http_status(:ok)
    expect(previous.reload.private_definition).to eq(original)
    get path, headers: headers
    rows = response.parsed_body.fetch('items')
    expect(rows.find { |row| row.fetch('code') == rule_input.fetch('code') }).not_to have_key('destination_schema_version')
    expect(rows.find { |row| row.fetch('code') == 'SYNTHETIC_SERVICE_DESK' }.fetch('destination_schema_version')).to eq(2)
  end

  it 'exposes only a currently authorized mapped destination in the source selector' do
    get "#{path}/source_context", headers: headers, params: { queue_id: queue.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('service_desk')).to eq(
      'configuration_available' => true, 'unit' => { 'id' => sd_unit.id.to_s, 'name' => sd_unit.name }
    )
    sd_membership.update!(active: false)
    get "#{path}/source_context", headers: headers, params: { queue_id: queue.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('service_desk')).to eq('configuration_available' => false)
  end

  it 'keeps configuration hidden after the native module is disabled even though Call Center remains enabled' do
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    account.disable_features!('jrc_service_desk')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.body).not_to include(sd_parameters.fetch('attributes').fetch('title'))
    expect(account.feature_enabled?('jrc_contact_center')).to be(true)
  end

  it 'resolves an authorized persisted reference outside the first lookup page without listing unrelated records' do
    21.times { |index| create(:jrc_sd_priority, unit: sd_unit, name: format('AAA SYNTHETIC priority %02d', index)) }
    sd_priority.update!(name: 'ZZZ SYNTHETIC selected priority')
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    labels = response.parsed_body.fetch('destination_presentations').fetch(sd_rule.fetch('code')).fetch('service_desk')
    expect(labels.fetch('priority')).to eq('id' => sd_priority.id.to_s, 'name' => sd_priority.name)
    expect(response.body).not_to include('AAA SYNTHETIC priority')
  end

  it 'withdraws a now-incompatible template and labels without rewriting its immutable snapshot after a mapping change' do
    save_service_desk_rule
    expect(response).to have_http_status(:ok)
    previous = JrcContactCenter::EndingActionVersion.where(account: account).sole
    original = previous.private_definition.deep_dup
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_other_unit.id.to_s))
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('items', 'destination_presentations')).to eq([[], {}])
    expect(response.body).not_to include(sd_parameters.fetch('attributes').fetch('title'), sd_unit.name)
    expect(previous.reload.private_definition).to eq(original)
  end
end
