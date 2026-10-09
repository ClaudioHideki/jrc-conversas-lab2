# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HelpDesk current scoped reporting and history', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_nico/helpdesk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Report company one') }
  let(:other_company) { JrcCustomers::Company.create!(account: sd_account, name: 'Report company two') }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id, other_company.id],
                                                         'operator_ids' => [sd_account_user.id])
    value['roles']['thiago'] = [sd_account_user.id]
    value['daily'].merge!('enabled' => true, 'recipients' => [sd_account_user.id], 'channels' => ['nico'])
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_account.enable_features!('jrc_relationship', 'jrc_customer_master')
    sd_as_admin!
  end

  def reporting_params(filters)
    { policy_id: policy.id, from: 1.day.ago.iso8601, filters: filters }
  end

  invalid_filters = [{ unexpected_scope: [1] }, { unit_ids: '1' }, { unit_ids: { arbitrary: 1 } }, []]
  %w[report kpis].each do |endpoint|
    invalid_filters.each_with_index do |filters, index|
      it "rejects malformed #{endpoint} filter #{index} rather than silently returning a broader scope" do
        expect do
          get "#{base}/#{endpoint}", params: reporting_params(filters), headers: headers
        end.not_to change(JrcNico::Helpdesk::DailyReport, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
        expect(JrcNico::Helpdesk::DeliveryReceipt.where(account: sd_account)).to be_empty
      end
    end
  end

  it 'parses canonical GET identifiers and narrows to the requested authorized company without scheduling a delivery' do
    selected = sd_ticket(company_id: company.id)
    sd_ticket(company_id: other_company.id)
    get "#{base}/report", params: reporting_params(company_ids: [company.id.to_s]), headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['ticket_ids']).to eq([selected.id])
    expect(response.parsed_body['filters']).to eq('company_ids' => [company.id])
    expect(response.parsed_body).to include('preview' => true, 'persisted' => false, 'delivery' => 'not_requested')
    expect(JrcNico::Helpdesk::DailyReport.where(account: sd_account)).to be_empty
    expect(JrcNico::Helpdesk::DeliveryReceipt.where(account: sd_account)).to be_empty
  end

  it 'denies a foreign unit instead of replacing it with the authorized pilot units' do
    get "#{base}/report", params: reporting_params(unit_ids: [sd_foreign_unit.id.to_s]), headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
  end

  %w[0 01 1.0].each do |identifier|
    it "rejects noncanonical identifier #{identifier} before reading an operational scope" do
      get "#{base}/report", params: reporting_params(unit_ids: [identifier]), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
    end
  end

  it 'rejects duplicate canonical identifiers and a reversed reporting window' do
    get "#{base}/kpis", params: reporting_params(unit_ids: [sd_unit.id, sd_unit.id.to_s]), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{base}/kpis", params: { policy_id: policy.id, from: Time.current.iso8601, until: 1.day.ago.iso8601 }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'reads an actual persisted daily version and its confirmed native receipt' do
    sd_ticket(company_id: company.id)
    report = JrcNico::Helpdesk::DailyReporter.new(policy, now: Time.utc(2026, 10, 8, 21)).call.fetch(0)
    get "#{base}/reports", params: { policy_id: policy.id, page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['reports'].pluck('id')).to eq([report.id])
    get "#{base}/reports/#{report.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(report.id)
    expect(response.parsed_body.fetch('receipts').map { |row| row['state'] }).to eq(['delivered'])
  end

  it 'omits an actual persisted daily version after its current ticket permissions are revoked' do
    sd_ticket(company_id: company.id)
    report = JrcNico::Helpdesk::DailyReporter.new(policy, now: Time.utc(2026, 10, 8, 21)).call.fetch(0)
    get "#{base}/reports/#{report.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(report.id)
    sd_membership.update!(active: false)
    get "#{base}/reports", params: { policy_id: policy.id, page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['reports']).to be_empty
    get "#{base}/reports/#{report.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
