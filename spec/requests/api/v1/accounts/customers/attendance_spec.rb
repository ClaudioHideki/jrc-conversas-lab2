require 'rails_helper'

RSpec.describe 'Cadastro Mestre attendance metrics', type: :request do
  context 'with conversations and reports' do
    let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:headers) { admin.create_new_auth_token }
    let(:company) { account.master_companies.create!(name: 'SYNTHETIC metrics company') }
    let(:contact) { create(:contact, account: account, company_id: company.id) }
    let(:conversation) { create(:conversation, account: account, contact: contact, created_at: '2026-11-02T03:01:00Z') }
    let(:url) { "/api/v1/accounts/#{account.id}/customers/companies/#{company.id}/attendance" }
    let(:period) { { from: '2026-11-02', to: '2026-11-02' } }

    before { account.enable_features!('jrc_customer_master') }

    it 'uses account-local inclusive dates, channel sources and public messages without leaking content' do
      conversation
      create(:conversation, account: account, contact: contact, created_at: '2026-11-02T02:59:00Z')
      create(:message, account: account, conversation: conversation, message_type: :incoming, private: false, content: 'PRIVATE_CONTENT_CANARY',
                       created_at: '2026-11-02T04:00:00Z')
      create(:message, account: account, conversation: conversation, message_type: :outgoing, private: false, created_at: '2026-11-02T04:01:00Z')
      create(:message, account: account, conversation: conversation, message_type: :outgoing, private: true, created_at: '2026-11-02T04:02:00Z')
      get url, params: period, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('period' => { 'from' => '2026-11-02', 'to' => '2026-11-02', 'timezone' => 'America/Sao_Paulo' },
                                              'messages' => { 'incoming' => 1, 'outgoing' => 1 })
      expect(response.parsed_body.dig('conversations', 'created')).to eq(1)
      expect(response.parsed_body.dig('conversations', 'by_channel')).to eq('Channel::WebWidget' => 1)
      expect(response.headers['Cache-Control']).to eq('no-store')
      expect(response.body).not_to include('PRIVATE_CONTENT_CANARY', 'email', 'phone_number')
    end

    it 'filters channels without changing the separate ticket measurement and rejects an unrecognized source' do
      conversation
      api_inbox = create(:channel_api, account: account).inbox
      create(:conversation, account: account, contact: contact, inbox: api_inbox, created_at: '2026-11-02T04:00:00Z')
      get url, params: period.merge(channel: 'Channel::Api'), headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('conversations', 'created')).to eq(1)
      expect(response.parsed_body['channels']).to match_array(%w[Channel::Api Channel::WebWidget])
      get url, params: period.merge(channel: 'foreign-channel'), headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it 'reports CSAT only from actual authorized replies and uses null when there are none' do
      get url, params: period, headers: headers
      expect(response.parsed_body['csat']).to include('available' => true, 'responses' => 0, 'satisfied_percent' => nil)
      message = create(:message, account: account, conversation: conversation)
      create(:csat_survey_response, account: account, contact: contact, conversation: conversation, message: message,
                                    rating: 5, feedback_message: 'SENSITIVE_FEEDBACK_CANARY', created_at: '2026-11-02T05:00:00Z')
      create(:csat_survey_response, rating: 1, created_at: '2026-11-02T05:00:00Z')
      get url, params: period, headers: headers
      expect(response.parsed_body['csat']).to include('responses' => 1, 'satisfied_percent' => 100.0)
      expect(response.body).not_to include('SENSITIVE_FEEDBACK_CANARY')
    end

    it 'does not expose hidden inboxes or infer report permission from directory access' do
      conversation
      agent = create(:user, account: account, role: :agent)
      get url, params: period, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('conversations', 'created')).to eq(0)
      expect(response.parsed_body['channels']).to be_empty
      expect(response.parsed_body['csat']).to eq('available' => false, 'reason' => 'permission')
      expect(response.parsed_body['conversation_sla']).to eq('available' => false, 'reason' => 'permission')
    end

    it 'keeps the actual enterprise conversation SLA records separate from ticket clocks' do
      account.enable_features!('sla')
      policy = create(:sla_policy, account: account)
      create(:applied_sla, account: account, conversation: conversation, sla_policy: policy, sla_status: :missed, created_at: '2026-11-02T04:00:00Z')
      get url, params: period, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['conversation_sla']).to include('available' => true, 'applied' => 1, 'with_recorded_miss' => 1)
      expect(response.parsed_body['ticket_sla']).not_to have_key('applied')
    end

    it 'rejects missing, inverted, oversized and invalid dates' do
      [{ from: '2026-11-02' }, { from: '2026-11-03', to: '2026-11-02' }, { from: '2024-01-01', to: '2026-11-02' },
       { from: '2026-02-30', to: '2026-11-02' }, { from: ['2026-11-02'], to: '2026-11-02' }].each do |values|
        get url, params: values, headers: headers
        expect(response).to have_http_status(:bad_request)
      end
    end

    it 'revalidates account and subject access on company and contact routes' do
      foreign = create(:account)
      foreign_company = foreign.master_companies.create!(name: 'FOREIGN_CANARY')
      get "/api/v1/accounts/#{account.id}/customers/companies/#{foreign_company.id}/attendance", params: period, headers: headers
      expect(response).to have_http_status(:not_found)
      get "/api/v1/accounts/#{foreign.id}/customers/companies/#{foreign_company.id}/attendance", params: period, headers: headers
      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      get "/api/v1/accounts/#{account.id}/customers/contacts/#{contact.id}/attendance", params: period, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('conversations', 'created')).to eq(0)
      get url, params: period
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with ticket-clock source isolation' do
    include_context 'JRC Service Desk domain'
    include JrcServiceDeskLifecycleFixtures
    include ActiveSupport::Testing::TimeHelpers
    before do
      travel_to Time.iso8601('2026-09-28T12:00:00Z')
      sd_as_admin!
      sd_account.enable_features!('jrc_customer_master')
    end

    it 'reads native calendar-aware running clocks only through the current ticket SLA grants without writing them' do
      lc_publish(definition: lc_definition(tracked: true))
      ticket = sd_ticket(opened_at: Time.current)
      lc_snapshot(ticket)
      lc_execute(ticket, 'pause', reason_code: 'customer')
      travel 3.hours
      clocks = ticket.sla_cycles.sole.sla_clocks.order(:id)
      original = clocks.map(&:attributes)
      path = "/api/v1/accounts/#{sd_account.id}/customers/contacts/#{sd_contact.id}/attendance"
      get path, params: { from: '2026-09-28', to: '2026-09-28' }, headers: sd_user.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ticket_sla']).to include('available' => true, 'clocks' => 2,
                                                         'currently_breached_running_clocks' => 1)
      expect(response.parsed_body.dig('conversation_sla', 'available')).to be(false)
      expect(clocks.reload.map(&:attributes)).to eq(original)
      role = create(:custom_role, account: sd_account,
                                  permissions: %w[contact_manage jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_customers_view])
      sd_account_user.update!(role: :agent, custom_role: role)
      get path, params: { from: '2026-09-28', to: '2026-09-28' }, headers: sd_user.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['ticket_sla']).to eq('available' => false, 'reason' => 'permission')
      expect(clocks.reload.map(&:attributes)).to eq(original)
    end
  end

  context 'with hidden shared response adapters' do
    include_context 'Service Desk survey models V3'
    it 'does not restore denied survey information through its native CSAT adapter' do
      payload = survey_payload.deep_dup
      payload['kind'] = 'csat'
      payload['questions'][0].merge!('min' => 1, 'max' => 5)
      publish_survey_model(payload)
      status = create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false)
      ticket = sd_ticket
      ticket.update!(status: status)
      survey = JrcRelationship::SurveyEngine.evaluate_event(source: ticket, event: 'closure', cycle_key: "metrics:#{ticket.id}").survey
      conversation = create(:conversation, account: sd_account, contact: sd_contact)
      message = create(:message, account: sd_account, conversation: conversation, content_type: :input_csat)
      CsatSurveyResponse.create!(account: sd_account, conversation: conversation, contact: sd_contact, message: message, rating: 5)
      survey.update!(metadata: survey.metadata.merge('sent_message_id' => message.id))
      get "/api/v1/accounts/#{sd_account.id}/customers/contacts/#{sd_contact.id}/attendance", headers: survey_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['csat']).to include('available' => true, 'responses' => 0, 'satisfied_percent' => nil)
    end
  end
end
