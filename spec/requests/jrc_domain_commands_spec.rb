require 'rails_helper'
require Rails.root.join('db/migrate/20261019140000_add_flow_domain_results')

RSpec.describe 'Native domain commands from Broker Flow', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:organization) { SecureRandom.uuid }
  let(:integration) { SecureRandom.uuid }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }
  let(:base) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/jrc_domain_commands" }
  let(:input) do
    { organization_id: organization, integration_id: integration, operation_id: SecureRandom.uuid, dispatch_proof: SecureRandom.uuid,
      inbox_id: inbox.id.to_s, remote_contact_id: conversation.contact_id.to_s,
      expected_control_revision: conversation.reload.jrc_effect_control_revision.to_s,
      operation: 'domain', value_json: { command: 'create_lead' }.to_json }
  end

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('jrc_broker', 'jrc_crm')
    JrcBrokerIntegration.create!(account: account, organization_id: organization, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration, instance_id: SecureRandom.uuid)
  end

  it 'advertises finite native commands and the current scoped owner directory separately from legacy effects' do
    identity = { organization_id: organization, integration_id: integration, inbox_id: inbox.id }
    get "/api/v1/accounts/#{account.id}/jrc_domain_commands/capabilities", headers: headers, params: identity
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('protocol' => 'jrc-domain-commands/1', 'commands' => %w[create_lead create_task create_meeting])
    expect(response.parsed_body.fetch('owners')).to include('id' => admin.id, 'name' => admin.name)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'commits a native lead and immutable causal event once, recovering a lost response by GET' do
    params = input
    expect { post base, params: params, headers: headers, as: :json }.to change(JrcCrm::Lead.where(account: account), :count).by(1)
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    expect(receipt.fetch('domain_result')).to include('command' => 'create_lead', 'resource_type' => 'JrcCrm::Lead', 'created' => true)
    expect(receipt.dig('domain_result',
                       'event')).to include('id' => params[:operation_id], 'causation_id' => params[:operation_id], 'type' => 'crm.lead.ready')
    expect { post base, params: params, headers: headers, as: :json }.not_to change(JrcCrm::Lead, :count)
    replayed = response.parsed_body
    get "#{base}/#{params[:operation_id]}", params: params.slice(:organization_id, :integration_id, :inbox_id, :dispatch_proof), headers: headers
    expect([replayed, response.parsed_body]).to all(eq(receipt))
    post base, params: params.merge(value_json: { command: 'create_task' }.to_json), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'uses native task and meeting creation with real resource receipts and no public message' do
    conversation
    original = conversation.reload.attributes
    %w[create_task create_meeting].each do |command|
      args = { command: command, owner_id: admin.id, title: 'Synthetic reviewed activity', due_at: 1.day.from_now.iso8601 }
      expect do
        post base, params: input.merge(operation_id: SecureRandom.uuid, dispatch_proof: SecureRandom.uuid, value_json: args.to_json),
                   headers: headers, as: :json
      end.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
      activity = JrcCrm::Activity.find(response.parsed_body.fetch('domain_result').fetch('resource_id'))
      expect(activity).to have_attributes(account_id: account.id, contact_id: conversation.contact_id, user_id: admin.id)
      expect(activity.activity_type).to eq(command == 'create_meeting' ? 'meeting' : 'task')
    end
    expect(conversation.reload.attributes).to eq(original)
  end

  it 'rejects revoked CRM access and a foreign owner without creating native records' do
    params = input
    account.disable_features!('jrc_crm')
    expect { post base, params: params, headers: headers, as: :json }.not_to change(JrcCrm::Lead, :count)
    expect(response).not_to have_http_status(:ok)
    account.enable_features!('jrc_crm')
    owner = create(:user, account: create(:account), role: :administrator)
    value = { command: 'create_task', owner_id: owner.id, title: 'Foreign owner', due_at: 1.day.from_now.iso8601 }
    expect { post base, params: params.merge(value_json: value.to_json), headers: headers, as: :json }.not_to change(JrcCrm::Activity, :count)
    expect(response).not_to have_http_status(:ok)
  end

  it 'refuses another meeting for the same owner and time while preserving the first receipt' do
    args = { command: 'create_meeting', owner_id: admin.id, title: 'Synthetic meeting', due_at: 1.day.from_now.iso8601 }
    params = input.merge(value_json: args.to_json)
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect do
      post base, params: params.merge(operation_id: SecureRandom.uuid), headers: headers, as: :json
    end.not_to change(JrcCrm::Activity, :count)
    expect(response).to have_http_status(:conflict)
    expect(JrcFlowEffectReceipt.where(account: account, operation: 'domain').count).to eq(1)
  end

  it 'rejects stale control, substituted contact, changed binding and arbitrary commands before effects' do
    params = input
    variants = [params.merge(expected_control_revision: (params[:expected_control_revision].to_i + 1).to_s),
                params.merge(remote_contact_id: create(:contact, account: account).id.to_s),
                params.merge(organization_id: SecureRandom.uuid), params.merge(value_json: { command: 'send_message' }.to_json)]
    variants.each do |invalid|
      expect { post base, params: invalid, headers: headers, as: :json }.not_to change(JrcCrm::Lead, :count)
      expect(response).not_to have_http_status(:ok)
    end
  end

  it 'rolls back the native effect if its durable receipt cannot commit' do
    allow(JrcFlowEffectReceipt).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)
    expect { post base, params: input, headers: headers, as: :json }.not_to change(JrcCrm::Lead, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'does not let the legacy receipt endpoint bypass a revoked native module grant' do
    params = input
    post base, params: params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    account.disable_features!('jrc_crm')
    get "#{base}/#{params[:operation_id]}", params: params.slice(:organization_id, :integration_id, :inbox_id, :dispatch_proof), headers: headers
    expect(response).not_to have_http_status(:ok)
    legacy = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/jrc_flow_effects/#{params[:operation_id]}"
    get legacy, params: params.slice(:organization_id, :dispatch_proof), headers: headers
    expect(response).to have_http_status(:conflict)
  end

  it 'refuses destructive schema rollback once a native domain receipt exists' do
    post base, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect { AddFlowDomainResults.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(JrcFlowEffectReceipt.where(account: account, operation: 'domain').count).to eq(1)
  end

  it 'does not advertise or execute domain commands before their additive migration is installed' do
    params = input
    ActiveRecord::Base.transaction(requires_new: true) do
      AddFlowDomainResults.new.down
      JrcFlowEffectReceipt.reset_column_information
      identity = { organization_id: organization, integration_id: integration, inbox_id: inbox.id }
      get "/api/v1/accounts/#{account.id}/jrc_domain_commands/capabilities", headers: headers, params: identity
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('commands' => [], 'owners' => [])
      expect(JrcDomainCommands::Request.available?).to be(false)
      expect(JrcCrm::ConversationLeadService).not_to receive(:new)
      params[:expected_control_revision] = conversation.reload.jrc_effect_control_revision.to_s
      expect { post base, params: params, headers: headers, as: :json }.not_to change(JrcCrm::Lead, :count)
      expect(response).to have_http_status(:conflict)
      raise ActiveRecord::Rollback
    end
  ensure
    JrcFlowEffectReceipt.reset_column_information
  end

  context 'with corporate coverage configured' do
    let(:company) { account.master_companies.create!(name: 'Synthetic issuer A', relationship_type: 'internal') }
    let(:unit) { account.jrc_crm_business_units.create!(name: 'Unit A', code: 'a', company_id: company.id) }
    let(:other_unit) { account.jrc_crm_business_units.create!(name: 'Unit B', code: 'b', company_id: company.id) }
    let(:coverage) do
      JrcCrm::UserBusinessUnit.create!(account: account, user: admin, scope: 'BUSINESS_UNIT',
                                       business_unit: unit, structure_managed: true)
    end

    before { coverage }

    it 'refuses a lead outside the administrator coverage for all three commands without receipts or activities' do
      lead = JrcCrm::ConversationLeadService.new(account: account, conversation: conversation, actor: admin).call.fetch(:lead)
      lead.update!(business_unit_id: other_unit.id)
      %w[create_lead create_task create_meeting].each do |command|
        args = if command == 'create_lead'
                 { command: command }
               else
                 { command: command, owner_id: admin.id, title: 'Scoped activity', due_at: 1.day.from_now.iso8601 }
               end
        post base, params: input.merge(value_json: args.to_json), headers: headers, as: :json
        expect(response).not_to have_http_status(:ok)
      end
      expect(JrcFlowEffectReceipt.where(account: account, operation: 'domain')).to be_empty
      expect(account.jrc_crm_activities).to be_empty
    end

    it 'keeps the native unit on new resources and blocks receipt access after coverage revocation' do
      args = { command: 'create_task', owner_id: admin.id, title: 'Scoped task', due_at: 1.day.from_now.iso8601 }
      params = input.merge(value_json: args.to_json)
      post base, params: params, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      activity = account.jrc_crm_activities.find(response.parsed_body.dig('domain_result', 'resource_id'))
      expect(activity.business_unit_id).to eq(unit.id)
      expect(activity.lead.business_unit_id).to eq(unit.id)
      coverage.update!(active: false)
      get "#{base}/#{params[:operation_id]}", params: params.slice(:organization_id, :integration_id, :inbox_id, :dispatch_proof), headers: headers
      expect(response).not_to have_http_status(:ok)
      post base, params: params, headers: headers, as: :json
      expect(response).not_to have_http_status(:ok)
    end

    it 'rejects an owner who cannot see the lead unit and rolls back the provisional lead' do
      owner = create(:user, account: account, role: :administrator)
      JrcCrm::UserBusinessUnit.create!(account: account, user: owner, scope: 'BUSINESS_UNIT',
                                       business_unit: other_unit, structure_managed: true)
      args = { command: 'create_task', owner_id: owner.id, title: 'Wrong coverage', due_at: 1.day.from_now.iso8601 }
      expect { post base, params: input.merge(value_json: args.to_json), headers: headers, as: :json }
        .not_to change(JrcCrm::Lead, :count)
      expect(response).not_to have_http_status(:ok)
      expect(account.jrc_crm_activities).to be_empty
    end
  end
end
