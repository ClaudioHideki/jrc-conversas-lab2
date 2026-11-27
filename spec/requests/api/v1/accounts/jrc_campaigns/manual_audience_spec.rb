require 'rails_helper'

RSpec.describe 'Campaign manual audience safety', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns" }
  let(:size) { 5 }
  let(:register_consents) { true }
  let(:contacts) do
    now = Time.current
    rows = Array.new(size) do |index|
      { account_id: account.id, name: "Synthetic #{index}", phone_number: "+551199#{format('%07d', index)}", created_at: now, updated_at: now }
    end
    ids = Contact.insert_all!(rows, returning: %w[id]).rows.flatten
    if register_consents
      JrcCampaigns::Consent.insert_all!(rows.map do |row|
        row.except(:name).merge(recorded_by_id: admin.id, purpose: 'whatsapp_campaigns', evidence: 'Synthetic explicit consent', granted_at: now)
      end)
    end
    account.contacts.where(id: ids).order(:id).to_a
  end
  let(:keys) { contacts.first(4).map { |contact| "contact:#{contact.id}" } }
  let(:selection) { { 'recipient_selection_mode' => 'include', 'recipient_selection_keys' => keys } }
  let(:attributes) do
    {
      name: 'Only selected recipients', inbox_id: inbox.id, audience_type: 'all_contacts', audience_config: selection,
      sending_window: { start: '00:00', end: '23:59', days: (0..6).to_a, timezone: 'UTC' },
      delay_min_seconds: 0, delay_max_seconds: 0,
      steps_attributes: [{ kind: 'template', position: 0, template_name: 'approved', template_language: 'pt_BR', template_params: {} }]
    }
  end
  let(:confirmation) do
    post "#{base}/audience_preview", params: { campaign: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch('selection_confirmation')
  end
  let(:campaign) do
    config = selection.merge('selection_confirmation' => confirmation)
    post base, params: { campaign: attributes.merge(audience_config: config) }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    JrcCampaigns::Campaign.find(response.parsed_body.fetch('id'))
  end

  around do |example|
    travel_to(Time.utc(2026, 11, 25, 15)) { example.run }
  end

  before do
    account.enable_features!('jrc_campaigns')
    inbox
    channel.update!(message_templates: [{ 'name' => 'approved', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                          'components' => [{ 'type' => 'BODY', 'text' => 'Synthetic' }] }])
  end

  context 'with 511 eligible consenting contacts' do
    let(:size) { 511 }

    it 'creates, reopens, approves, queues and dispatches exactly four, excluding the other 507' do
      approved_ids = contacts.first(4).map(&:id)
      consent_records = JrcCampaigns::Consent.where(account: account).order(:id).map(&:attributes)
      get "#{base}/#{campaign.id}", headers: headers
      expect(response.parsed_body).to include('estimated_recipients' => 4, 'audience_type' => 'all_contacts')
      expect(response.parsed_body.dig('audience_config', 'recipient_selection_keys')).to eq(keys)
      post "#{base}/#{campaign.id}/request_review", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('review_snapshot', 'recipients').map { |row| row['contact_id'] }).to eq(approved_ids)
      post "#{base}/#{campaign.id}/approve", params: { digest: campaign.reload.review_digest }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      clear_enqueued_jobs
      post "#{base}/#{campaign.id}/launch", headers: headers
      expect(response).to have_http_status(:ok)
      execution = JrcCampaigns::LaunchService.new(campaign.reload).perform
      expect(execution.total_count).to eq(4)
      expect(execution.recipients.pluck(:contact_id)).to match_array(approved_ids)
      dispatches = enqueued_jobs.select { |job| job[:job] == JrcCampaigns::DispatchStepJob }
      expect(dispatches.map { |job| job[:args].first }).to match_array(execution.recipients.pluck(:id))
      dispatched_numbers = []
      request = stub_request(:post, %r{https://graph.facebook.com/.*/messages}).to_return do |req|
        destination = JSON.parse(req.body).fetch('to')
        dispatched_numbers << destination.delete_prefix('+')
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: "wamid.synthetic.#{destination}" }] }.to_json }
      end
      execution.recipients.reload.each { |recipient| JrcCampaigns::DispatchStepService.new(recipient: recipient, step: campaign.steps.first).perform }
      expect(execution.recipients.reload.pluck(:status)).to eq(%w[sent sent sent sent]), execution.recipients.pluck(:error_message).inspect
      expect(request).to have_been_requested.times(4)
      expect(dispatched_numbers).to match_array(contacts.first(4).map { |contact| contact.phone_number.delete_prefix('+') })
      expect(campaign.recipients.where.not(contact_id: approved_ids)).to be_empty
      expect(JrcCampaigns::Consent.where(account: account).order(:id).map(&:attributes)).to eq(consent_records)
    end
  end

  it 'rejects first creation if all_contacts overwrites the four-person selection after preview' do
    proof = confirmation
    broadened = { recipient_selection_mode: 'exclude', recipient_selection_keys: [], selection_confirmation: proof }
    expect do
      post base, params: { campaign: attributes.merge(audience_config: broadened) }, headers: headers, as: :json
    end.not_to change(JrcCampaigns::Campaign, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context 'with 511 contacts and no consent registration' do
    let(:size) { 511 }
    let(:register_consents) { false }

    it 'still queues and dispatches only the four manually selected recipients' do
      expected = contacts.first(4).map(&:phone_number)
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      execution = JrcCampaigns::LaunchService.new(campaign).perform
      expect(execution.total_count).to eq(4)
      expect(execution.recipients.pluck(:phone_number)).to match_array(expected)
      sent_to = []
      request = stub_request(:post, %r{https://graph.facebook.com/.*/messages}).to_return do |req|
        destination = JSON.parse(req.body).fetch('to')
        sent_to << "+#{destination.delete_prefix('+')}"
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: "wamid.synthetic.#{destination}" }] }.to_json }
      end
      execution.recipients.reload.each { |recipient| JrcCampaigns::DispatchStepService.new(recipient: recipient, step: campaign.steps.first).perform }
      expect(sent_to).to match_array(expected)
      expect(request).to have_been_requested.times(4)
      expect(execution.recipients.reload.pluck(:status)).to eq(%w[sent sent sent sent])
      expect(JrcCampaigns::Consent.where(account: account)).to be_empty
    end
  end

  it 'rejects updates that broaden the audience or remove its confirmation' do
    id = campaign.id
    [selection.merge('recipient_selection_keys' => []), { recipient_selection_mode: 'exclude', recipient_selection_keys: [] }].each do |config|
      patch "#{base}/#{id}", params: { campaign: { audience_config: config } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(campaign.reload.audience_config['recipient_selection_keys']).to eq(keys)
  end

  it 'rejects review and launch when persisted selection diverges from its preview confirmation' do
    config = campaign.audience_config.merge('recipient_selection_mode' => 'exclude', 'recipient_selection_keys' => [])
    campaign.update_columns(audience_config: config)
    post "#{base}/#{campaign.id}/request_review", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect { JrcCampaigns::LaunchService.new(campaign.reload).perform }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.executions).to be_empty
  end

  it 'never dispatches a queued recipient that is not in the approved four-person snapshot' do
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    execution = JrcCampaigns::LaunchService.new(campaign).perform
    outsider = contacts.last
    recipient = execution.recipients.create!(campaign: campaign, contact: outsider, inbox: inbox, destination: outsider.phone_number,
                                             phone_number: outsider.phone_number)
    JrcCampaigns::DispatchStepService.new(recipient: recipient, step: campaign.steps.first).perform
    expect(recipient.reload).to be_skipped
    expect(recipient.error_message).to include('diverge')
    expect(WebMock).not_to have_requested(:post, /graph.facebook.com/)
  end

  it 'rejects a confirmation and selection copied from another account' do
    foreign = create(:contact)
    config = selection.merge('selection_confirmation' => confirmation, 'recipient_selection_keys' => ["contact:#{foreign.id}"])
    post base, params: { campaign: attributes.merge(audience_config: config) }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.where(account: account).count).to eq(5)
  end

  it 'allows an explicit select-all with its own matching confirmation' do
    contacts
    attributes[:audience_config] = { 'recipient_selection_mode' => 'exclude', 'recipient_selection_keys' => [] }
    attributes[:audience_config]['selection_confirmation'] = confirmation
    post base, params: { campaign: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    record = JrcCampaigns::Campaign.find(response.parsed_body.fetch('id'))
    record.request_review!
    expect(record.review_snapshot['recipients'].size).to eq(5)
  end

  it 'never treats deselect-all as a request to use the entire source' do
    selection['recipient_selection_keys'] = []
    record = campaign
    expect(record.estimated_recipients).to eq(0)
    expect { record.request_review! }.to raise_error(ActiveRecord::RecordInvalid)
    expect { record.launch! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(record.recipients).to be_empty
  end

  it 'keeps selection flags when searching and paging the available audience' do
    2.times do |page|
      post "#{base}/audience_preview", params: { campaign: attributes, include_recipients: true, recipient_page: page + 1,
                                                 recipient_per_page: 3, recipient_search: 'Synthetic' }, headers: headers, as: :json
      data = response.parsed_body
      expect(data['estimated_recipients']).to eq(4)
      expect(data.dig('recipient_pagination', 'total')).to eq(5)
      data['recipients'].each { |row| expect(row['selected']).to eq(keys.include?(row['selection_key'])) }
    end
  end

  it 'rejects approval and queue creation after selection changes outside the approved review' do
    campaign.request_review!
    proof = campaign.review_digest
    campaign.update_columns(audience_config: campaign.audience_config.merge('recipient_selection_keys' => []))
    post "#{base}/#{campaign.id}/approve", params: { digest: proof }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    clear_enqueued_jobs
    post "#{base}/#{campaign.id}/launch", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(enqueued_jobs.select { |job| job[:job] == JrcCampaigns::LaunchJob }).to be_empty
  end
end
