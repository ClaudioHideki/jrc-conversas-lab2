require 'rails_helper'

RSpec.describe 'Published customer segments in campaign drafts and previews', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns" }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Campaign customers', kind: 'segment', modules: ['campaigns']) }
  let(:company) { account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:contact) { create(:contact, account: account, company_id: company.id, email: 'selected@example.test') }
  let(:other) { create(:contact, account: account, email: 'unmatched@example.test') }
  let(:fields) do
    { name: 'Selected draft', delivery_channel: 'email', audience_type: 'all_contacts',
      audience_config: { customer_filters: { customer_segment_id: taxonomy.id } } }
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_campaigns')
    contact
    other
  end

  it 'previews the published canonical audience using the authenticated administrator and native recipient pagination' do
    post "#{root}/audience_preview", headers: headers, as: :json,
                                     params: { campaign: fields.merge(created_by_id: 0), include_recipients: true, recipient_per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('recipients').pluck('contact_id')).to eq([contact.id])
    expect(response.parsed_body.fetch('recipient_pagination')).to include('total' => 1, 'per_page' => 1)
    expect(JrcCampaigns::Campaign.where(account: account)).to be_empty
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'persists only a draft with the authenticated creator and does not execute or send it' do
    post root, headers: headers, params: { campaign: fields.merge(created_by_id: 0) }, as: :json
    expect(response).to have_http_status(:created)
    campaign = account.jrc_campaigns.find(response.parsed_body.fetch('id'))
    expect(campaign).to have_attributes(created_by_id: actor.id, status: 'draft', estimated_recipients: 1)
    expect(campaign.audience_config.dig('customer_filters', 'customer_segment_id')).to eq(taxonomy.id)
    expect(campaign.executions).to be_empty
    expect(JrcCampaigns::Recipient.where(campaign: campaign)).to be_empty
  end

  it 'does not borrow the stored creators corporate coverage when another administrator updates the audience' do
    campaign = account.jrc_campaigns.create!(name: 'Legacy draft', delivery_channel: 'email', created_by: actor)
    restricted = create(:user, account: account, role: :administrator)
    company.update!(relationship_type: 'internal')
    account.jrc_crm_business_units.create!(name: 'Selected unit', code: 'CAM-HTTP-A', company_id: company.id)
    issuer = account.master_companies.create!(name: 'Other operator', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Other unit', code: 'CAM-HTTP-B', company_id: issuer.id)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'GROUP', structure_managed: true)
    account.jrc_crm_user_business_units.create!(user: restricted, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    original = campaign.attributes
    patch "#{root}/#{campaign.id}", headers: restricted.create_new_auth_token, params: { campaign: fields }, as: :json
    expect(response).not_to have_http_status(:ok)
    expect(campaign.reload.attributes).to eq(original)
  end

  it 'retains the legacy draft workflow when the customer master module is disabled and no extra segment is requested' do
    account.disable_features!('jrc_customer_master')
    post root, headers: headers, params: { campaign: fields.except(:audience_config) }, as: :json
    expect(response).to have_http_status(:created)
    campaign = account.jrc_campaigns.find(response.parsed_body.fetch('id'))
    expect(campaign).to be_draft
    post "#{root}/audience_preview", headers: headers, params: { campaign: fields }, as: :json
    expect(response).not_to have_http_status(:ok)
  end

  it 'rejects foreign and unpublished segment identifiers without creating a draft' do
    taxonomy.update!(modules: ['crm'])
    post "#{root}/audience_preview", headers: headers, params: { campaign: fields }, as: :json
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    segment = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign campaigns', kind: 'segment', modules: ['campaigns'])
    input = fields.deep_merge(audience_config: { customer_filters: { customer_segment_id: segment.id } })
    post root, headers: headers, params: { campaign: input }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(account.jrc_campaigns).to be_empty
  end

  it 'rejects a published segment for sanitized lists instead of silently ignoring it' do
    post "#{root}/audience_preview", headers: headers, params: { campaign: fields.merge(audience_type: 'sanitized_list') }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.jrc_campaigns).to be_empty
  end
end
