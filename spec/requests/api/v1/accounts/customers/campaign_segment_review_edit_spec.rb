require 'rails_helper'

RSpec.describe 'Editing a reviewed campaign customer audience', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns" }
  let(:replacement_fields) { { audience_config: { customer_filters: { customer_segment_id: replacement.id } } } }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Reviewed customers', kind: 'segment', modules: ['campaigns']) }
  let(:replacement) { JrcCustomers::Taxonomy.create!(account: account, name: 'Replacement audience', kind: 'segment', modules: ['campaigns']) }
  let(:company) { account.master_companies.create!(name: 'Canonical customer', segment: taxonomy.name) }
  let(:contact) { create(:contact, account: account, company_id: company.id, email: 'reviewed@example.test') }
  let(:campaign) do
    account.jrc_campaigns.create!(
      created_by: actor, name: 'Reviewed local draft', delivery_channel: 'email',
      audience_config: { customer_filters: { customer_segment_id: taxonomy.id } }
    )
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_campaigns')
    contact
  end

  it 'requires fresh approval after the authenticated API changes the segment even when the same contact still matches' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: replacement, contact: contact, mode: 'include')
    campaign.request_review!
    campaign.approve!(actor, campaign.review_digest)
    expect(JrcCampaigns::ApprovalService.new(campaign).locally_valid?).to be(true)

    patch "#{root}/#{campaign.id}", headers: headers, as: :json, params: { campaign: replacement_fields }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('approval_valid')).to be(false)
    expect(campaign.reload.audience_config.dig('customer_filters', 'customer_segment_id')).to eq(replacement.id)
    expect { campaign.ensure_approved! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(campaign.executions).to be_empty
    expect(JrcCampaigns::Recipient.where(campaign: campaign)).to be_empty
  end
end
