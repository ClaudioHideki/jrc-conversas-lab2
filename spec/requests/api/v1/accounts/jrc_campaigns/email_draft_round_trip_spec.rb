require 'rails_helper'

RSpec.describe 'Email campaign draft editing contract', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns" }
  let(:fields) do
    { name: 'Email draft', delivery_channel: 'email', audience_type: 'all_contacts',
      steps_attributes: [{ position: 0, kind: 'email', subject: 'Original subject', body: 'Local draft only' }] }
  end
  let(:campaign) { account.jrc_campaigns.create!(fields.merge(created_by: actor)) }

  before { account.enable_features!('jrc_campaigns') }

  it 'returns the email channel and subject when creating a draft' do
    post root, headers: headers, params: { campaign: fields }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('delivery_channel' => 'email', 'status' => 'draft')
    expect(response.parsed_body.fetch('steps').sole).to include('subject' => 'Original subject', 'kind' => 'email')
  end

  it 'returns the stored channel and subject when opening a draft for editing' do
    get "#{root}/#{campaign.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('delivery_channel' => 'email', 'status' => 'draft')
    expect(response.parsed_body.fetch('steps').sole).to include('subject' => 'Original subject', 'kind' => 'email')
  end

  it 'preserves the email channel and changed subject without launching or sending' do
    patch "#{root}/#{campaign.id}", headers: headers, as: :json,
                                    params: { campaign: { delivery_channel: 'email',
                                                          steps_attributes: [{ id: campaign.steps.sole.id, subject: 'Edited subject' }] } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('delivery_channel' => 'email', 'status' => 'draft')
    expect(response.parsed_body.fetch('steps').sole).to include('subject' => 'Edited subject')
    expect(campaign.reload).to have_attributes(delivery_channel: 'email', status: 'draft')
    expect(campaign.steps.sole.subject).to eq('Edited subject')
    expect(campaign.executions).to be_empty
    expect(JrcCampaigns::Recipient.where(campaign: campaign)).to be_empty
  end
end
