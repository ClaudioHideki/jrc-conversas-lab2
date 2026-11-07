require 'rails_helper'

RSpec.describe 'Native CRM activity completion scope', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:lead) { create(:jrc_crm_lead, account: account, owner: actor) }
  let(:activity) { create(:jrc_crm_activity, account: account, user: actor, lead: lead, deal: nil) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/activities/#{activity.id}/complete" }

  before { account.enable_features!('jrc_crm') }

  it 'persists completion of the visible native record without replacing source ownership or dates' do
    original = activity.attributes.except('status', 'completed_at', 'updated_at')

    post url, headers: actor.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(activity.reload).to have_attributes(status: 'completed', completed_at: be_present)
    expect(activity.attributes.except('status', 'completed_at', 'updated_at')).to eq(original)
    expect(response.parsed_body.dig('lead', 'id')).to eq(lead.id)
  end

  it 'denies another owners completion before changing the native record' do
    other = create(:user, account: account, role: :agent)
    original = activity.attributes.deep_dup

    post url, headers: other.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(activity.reload.attributes).to eq(original)
  end

  it 'denies a foreign account completion without changing the original native record' do
    foreign = create(:account)
    foreign.enable_features!('jrc_crm')
    outsider = create(:user, account: foreign, role: :administrator)
    original = activity.attributes.deep_dup

    post "/api/v1/accounts/#{foreign.id}/crm/activities/#{activity.id}/complete", headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(activity.reload.attributes).to eq(original)
  end
end
