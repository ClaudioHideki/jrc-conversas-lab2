require 'rails_helper'
require 'csv'

RSpec.describe 'Campaign consent CSV import', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_campaigns/consents" }
  let(:phone) { '+5511999999000' }
  let(:date) { 1.day.ago.iso8601 }
  let(:csv) { CSV.generate_line(%w[phone_number source granted_at evidence]) + CSV.generate_line([phone, 'Synthetic form', date, 'Recurring tests and campaigns authorized']) }
  before { account.enable_features!('jrc_campaigns') }

  it 'previews a BOM semicolon CSV without creating consent or sending' do
    content = "\uFEFFphone_number;source;granted_at;evidence\n#{phone};Form;#{date};\"Explicit recurring permission; reference 12\"\n"
    post "#{base}/import_preview", headers: admin.create_new_auth_token, params: { csv: content }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('total' => 1, 'ready' => 1, 'errors' => 0)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
    expect(JrcCampaigns::TestDelivery.where(account: account)).to be_empty
  end

  it 'records source, actual grant date, evidence, author and account with explicit recurring confirmation' do
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('imported' => 1, 'existing' => 0)
    consent = JrcCampaigns::Consent.find_by!(account: account, phone_number: phone)
    expect(consent).to have_attributes(recorded_by: admin, purpose: 'whatsapp_campaigns', revoked_at: nil, granted_at: Time.iso8601(date))
    expect(consent.evidence).to include('Synthetic form', 'Recurring tests and campaigns authorized')
    expect(JrcCampaigns::TestDelivery.where(account: account)).to be_empty
  end

  it 'requires a JSON boolean confirmation, including for direct API requests' do
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: 'true' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'preserves existing active grants when repeating the import' do
    2.times do
      post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
      expect(response).to have_http_status(:created)
    end
    expect(response.parsed_body).to include('imported' => 0, 'existing' => 1)
    expect(JrcCampaigns::Consent.where(account: account).count).to eq(1)
  end

  it 'rejects the entire batch when any row is invalid' do
    content = csv + CSV.generate_line(['invalid', 'Form', date, 'Permission'])
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: content, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'detects normalized duplicates and missing source or evidence per row' do
    content = csv + CSV.generate_line(['5511999999000', 'Form', date, 'Permission']) + CSV.generate_line(['5511999999001', '', date, ''])
    post "#{base}/import_preview", headers: admin.create_new_auth_token, params: { csv: content }, as: :json
    expect(response.parsed_body).to include('errors' => 2, 'ready' => 1)
    expect(response.parsed_body['rows'][1]['reason']).to match(/repetido/)
    expect(response.parsed_body['rows'][2]['reason']).to match(/origem e evidência/)
  end

  it 'rejects malformed CSV, incorrect columns, empty input, oversized files and row counts' do
    ["phone_number,source,granted_at,evidence\n\"unclosed", "phone\n#{phone}", 'phone_number,source,granted_at,evidence', 'x' * (1.megabyte + 1),
     CSV.generate_line(%w[phone_number source granted_at evidence]) + (CSV.generate_line([phone, 'Form', date, 'Permission']) * 501)].each do |content|
      post "#{base}/import_preview", headers: admin.create_new_auth_token, params: { csv: content }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'rejects future dates, invalid dates and timestamps without a timezone' do
    [1.day.from_now.iso8601, 'not-a-date', '2026-01-01T12:00:00'].each do |timestamp|
      content = CSV.generate_line(%w[phone_number source granted_at evidence]) + CSV.generate_line([phone, 'Form', timestamp, 'Permission'])
      post "#{base}/import_preview", headers: admin.create_new_auth_token, params: { csv: content }, as: :json
      expect(response.parsed_body['errors']).to eq(1)
    end
  end

  it 'does not silently broaden historical grants or reuse authorization predating revocation' do
    old = JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'Old', granted_at: 3.days.ago)
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(old.reload.revoked_at).to be_nil
    old.update!(revoked_at: 1.hour.ago)
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.where(account: account).count).to eq(1)
  end

  it 'rechecks revocation at import after preview' do
    post "#{base}/import_preview", headers: admin.create_new_auth_token, params: { csv: csv }, as: :json
    expect(response.parsed_body['ready']).to eq(1)
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, purpose: 'whatsapp_campaigns',
                                 granted_at: 2.days.ago, revoked_at: 1.hour.ago, evidence: 'Revoked')
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.active.where(account: account)).to be_empty
  end

  it 'accepts a genuinely new grant after revocation and preserves the revoked record' do
    old = JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, purpose: 'whatsapp_campaigns',
                                      granted_at: 4.days.ago, revoked_at: 2.days.ago, evidence: 'Original revoked permission')
    original = old.attributes
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:created)
    expect(old.reload.attributes).to eq(original)
    expect(JrcCampaigns::Consent.active.where(account: account).sole.granted_at).to eq(Time.iso8601(date))
  end

  it 'makes an existing sanitized-list recipient eligible on refresh without launching the campaign' do
    inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
    list = JrcCampaigns::Sanitizer.new(account: account, user: admin, name: 'Synthetic list', entries: [{ phone: phone }]).perform
    campaign = JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Import QA',
                                             audience_type: 'sanitized_list', audience_config: { sanitized_list_id: list.id })
    expect(JrcCampaigns::AudienceResolver.new(campaign).estimated_count).to eq(0)
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcCampaigns::AudienceResolver.new(campaign).estimated_count).to eq(1)
    expect(campaign.reload).to be_draft
    expect(campaign.executions).to be_empty
  end

  it 'isolates accounts and keeps blacklist protections after import' do
    other = create(:account)
    JrcCampaigns::Consent.create!(account: other, recorded_by: admin, phone_number: phone, evidence: 'Other account', granted_at: 2.days.ago)
    account.jrc_campaign_blacklists.create!(phone_number: phone, reason: 'Do not send')
    post "#{base}/import_csv", headers: admin.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone, purpose: 'whatsapp_campaigns').rejection_reason).to match(/blacklist/)
    expect(JrcCampaigns::Consent.where(account: other).sole.evidence).to eq('Other account')
  end

  it 'forbids agents from previewing or importing grants' do
    agent = create(:user, account: account, role: :agent)
    %w[import_preview import_csv].each do |action|
      post "#{base}/#{action}", headers: agent.create_new_auth_token, params: { csv: csv, operator_confirmed: true }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end
end
