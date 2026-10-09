require 'rails_helper'

RSpec.describe 'HelpDesk exact incident campaign drafts', type: :request do
  include_context 'NICO HelpDesk native action chain'

  let(:selected_rule) { 'R04' }
  let(:selected_group) { 'C1' }
  let(:companies) { [company, *Array.new(3) { JrcCustomers::Company.create!(account: sd_account, name: SecureRandom.uuid) }] }
  let(:mass_tickets) do
    sd_contact.update!(company_id: company.id, phone_number: '+5511991112233')
    [ticket, *companies.drop(1).map do |customer|
      contact = create(:contact, account: sd_account, company_id: customer.id)
      sd_ticket(company_id: customer.id, requester: contact)
    end]
  end
  let(:incident) do
    event
    JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: { title: 'Reviewed native mass incident', severity: 'high', ticket_ids: mass_tickets.map(&:id) },
      idempotency_key: SecureRandom.uuid)
  end
  let(:inbox) do
    create(:channel_whatsapp, account: sd_account, sync_templates: false, validate_provider_config: false).inbox
  end
  let(:draft_input) { { 'campaign' => { 'incident_id' => incident.id, 'inbox_id' => inbox.id, 'name' => 'Human incident draft' } } }

  before do
    sd_account.enable_features!('jrc_campaigns')
    definition['company_ids'] = companies.map(&:id)
  end

  def native_action_event
    mass_tickets.each do |row|
      JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row, company_id: row.company_id,
        case_kind: 'defect', defect_key: 'synthetic.mass')
    end
    policy
    captured = JrcNico::Helpdesk::Capture.new(sd_account_user).call(ticket: ticket.reload, trigger: 'monitor',
      origin_key: "campaign-draft:#{ticket.id}")
    expect(captured.pluck(:rule_key)).to eq(['R04'])
    expect(captured.first.evidence.fetch('ticket_ids')).to eq(mass_tickets.map(&:id).sort)
    JrcNico::Helpdesk::EventJob.perform_now(captured.first.id)
    expect(captured.first.reload.state).to eq('prepared')
    captured.first
  end

  it 'uses Capture through Approval and native persisted draft plus exact authorized readback, with no dispatch' do
    input = draft_input
    queued_before = ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job].name.start_with?('JrcCampaigns::') }
    messages_before = Message.count
    approval = nil
    expect { approval = prepare_native(input, 'prepare_incident_campaign') }.not_to change(JrcCampaigns::Campaign, :count)
    expect { approve_native(approval) }.to change(JrcCampaigns::Campaign, :count).by(1)
    command = approved_action(approval)
    row = JrcCampaigns::Campaign.find(command.result.fetch('id'))
    expect(row).to have_attributes(account_id: sd_account.id, created_by_id: sd_user.id, status: 'draft', trigger_type: 'manual',
      audience_type: 'sanitized_list', inbox_id: nil, approved_at: nil, approved_by_id: nil, scheduled_at: nil, message_body: '')
    expect(row.campaign_inboxes.first).to have_attributes(inbox_id: inbox.id, enabled: false)
    expect(row.sending_inbox_links).to be_empty
    expect(row.steps).to be_empty
    expect(row.executions).to be_empty
    expect(row.recipients).to be_empty
    list = sd_account.jrc_campaign_sanitized_lists.find(row.audience_config.fetch('sanitized_list_id'))
    expect(list.entries.pluck(:metadata).pluck('contact_id').sort).to eq(mass_tickets.map(&:requester_id).sort)
    expect(list.entries.pluck(:metadata).flat_map { |value| value.fetch('ticket_ids') }.sort).to eq(mass_tickets.map(&:id).sort)
    expect(row.metadata.dig('nico_helpdesk', 'command_id')).to eq(command.id)
    expect(command.result.dig('provenance', 'list_digest')).to match(/\A[a-f0-9]{64}\z/)
    expect(JrcCampaigns::AudienceResolver.new(row).entries).to be_empty # no consent was invented
    get "/api/v1/accounts/#{sd_account.id}/jrc_campaigns/campaigns/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(row.id)
    get "#{base}/approvals", headers: headers
    expect(response.parsed_body.fetch('approvals').pluck('id')).to include(approval.id)
    expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:ok)
    expect(Message.count).to eq(messages_before)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.count { |job| job[:job].name.start_with?('JrcCampaigns::') }).to eq(queued_before)
    expect(a_request(:any, %r{https?://})).not_to have_been_made
  end

  it 'offers current exact native sources without selecting an Incident or Inbox or creating a draft' do
    incident
    inbox
    result = action_preview({})
    expect(result.dig('draft_choices', 'campaign', 'incidents').pluck('id')).to eq([incident.id])
    expect(result.dig('draft_choices', 'campaign', 'inboxes').pluck('id')).to include(inbox.id)
    expect(result.fetch('actions')).to be_empty
    expect(JrcCampaigns::Campaign.where(account: sd_account)).to be_empty
    expect(JrcCampaigns::SanitizedList.where(account: sd_account)).to be_empty
  end

  it 'rejects global audience, browser phones, launch fields, forged ids and missing reviewed name' do
    values = draft_input
    [values.deep_merge('campaign' => { 'audience_type' => 'all_contacts' }),
     values.deep_merge('campaign' => { 'ticket_ids' => mass_tickets.map(&:id) }),
     values.deep_merge('campaign' => { 'phone' => '+5511999990000' }),
     values.deep_merge('campaign' => { 'status' => 'running' }),
     values.deep_merge('campaign' => { 'incident_id' => incident.id.to_s }),
     values.deep_merge('campaign' => { 'name' => nil })].each do |input|
      post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: input }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
    end
    expect(JrcCampaigns::Campaign.where(account: sd_account)).to be_empty
  end

  it 'rejects an Incident with a foreign or missing child rather than silently intersecting cohorts' do
    values = draft_input
    JrcServiceDesk::Ticket.where(id: mass_tickets.last.id).update_all(incident_id: nil)
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: values }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcCampaigns::Campaign.where(account: sd_account)).to be_empty
  end

  it 'rejects a foreign account Inbox without a campaign or sanitized list write' do
    values = draft_input.deep_merge('campaign' => { 'inbox_id' => create(:inbox, account: sd_foreign_account).id })
    post "#{base}/group_preview", params: { event_id: event.id, group_key: selected_group, input: values }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcCampaigns::SanitizedList.where(account: sd_account)).to be_empty
  end

  it 'invalidates a prepared cohort when a blacklist or native consent changes before approval' do
    approval = prepare_native(draft_input, 'prepare_incident_campaign')
    JrcCampaigns::Blacklist.create!(account: sd_account, phone_number: sd_contact.phone_number, created_by: sd_user)
    expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(approval.reload.state).to eq('pending')
    expect(JrcCampaigns::SanitizedList.where(account: sd_account)).to be_empty
  end

  it 'rechecks current campaign permission before writing and hides terminal receipts after revocation' do
    approval = prepare_native(draft_input, 'prepare_incident_campaign')
    sd_account.disable_features!('jrc_campaigns')
    expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(approval.reload.state).to eq('pending')
    verify_receipt_hidden(approval)
  end

  it 'rechecks originating Unit membership before draft creation' do
    approval = prepare_native(draft_input, 'prepare_incident_campaign')
    sd_membership.update!(active: false)
    expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:not_found)
    expect(JrcCampaigns::SanitizedList.where(account: sd_account)).to be_empty
  end

  it 'does not retry an unknown outcome as if a draft had never been created' do
    approval = prepare_native(draft_input, 'prepare_incident_campaign')
    approval.update!(state: 'unknown')
    approval.command.update!(status: 'unknown')
    expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(approval.reload.state).to eq('unknown')
    expect(JrcCampaigns::SanitizedList.where(account: sd_account)).to be_empty
  end

  it 'rejects canonical customer drift before approval' do
    approval = prepare_native(draft_input, 'prepare_incident_campaign')
    sd_contact.update!(company_id: companies.last.id)
    expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:unauthorized)
    expect(approval.reload.state).to eq('pending')
  end

  it 'rejects a different second Command for the same completed event without duplicate lists' do
    approval = prepare_native(draft_input, 'prepare_incident_campaign')
    approve_native(approval)
    approved_action(approval)
    input = draft_input.deep_merge('campaign' => { 'name' => 'Different human name' })
    preview = action_preview(input)
    action = preview.fetch('actions').find { |row| row.fetch('tool') == 'prepare_incident_campaign' }
    expect do
      post "#{base}/group_prepare", params: { event_id: event.id, group_key: selected_group, input: input,
        tool: action.fetch('tool'), arguments: action.fetch('arguments'), preview_digest: preview.fetch('preview_digest') },
        headers: headers, as: :json
    end.not_to change(JrcCampaigns::SanitizedList, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Campaign.where(account: sd_account).count).to eq(1)
  end

  %w[normalized_phone audience_type cohort_child inbox_link].each do |mutation|
    it "hides the exact receipt when its persisted #{mutation} proof is changed" do
      approval = prepare_native(draft_input, 'prepare_incident_campaign')
      approve_native(approval)
      command = approved_action(approval)
      row = JrcCampaigns::Campaign.find(command.result.fetch('id'))
      case mutation
      when 'normalized_phone'
        list = sd_account.jrc_campaign_sanitized_lists.find(row.audience_config.fetch('sanitized_list_id'))
        list.entries.first.update!(normalized_phone: '+5511999990000')
      when 'audience_type' then row.update!(audience_type: 'all_contacts', audience_config: {})
      when 'cohort_child' then sd_ticket(company_id: company.id).update!(incident: incident)
      when 'inbox_link' then row.campaign_inboxes.first.update!(enabled: true)
      end
      verify_receipt_hidden(approval)
      expect { approve_native(approval) }.not_to change(JrcCampaigns::Campaign, :count)
      expect(response.parsed_body).to be_nil
      expect(row.reload.executions).to be_empty
    end
  end
end
