require 'rails_helper'

RSpec.describe 'Native CRM activity origin visibility', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:pipeline) { JrcCrm::DefaultPipelineService.new(account).perform }
  let(:stage) { pipeline.stages.active.order(:position).first }
  let(:private_deal) { create(:jrc_crm_deal, account: account, owner: other, pipeline: pipeline, stage: stage, title: 'Synthetic hidden origin') }
  let(:private_lead) { create(:jrc_crm_lead, account: account, owner: other) }
  let(:own_lead) { create(:jrc_crm_lead, account: account, owner: actor) }
  let(:payload) do
    { activity: { activity_type: 'follow_up', title: 'Synthetic bounded activity', due_at: '2026-11-10T10:30' } }
  end

  before { account.enable_features!('jrc_crm') }

  it 'cannot create and serialize an activity for a deal hidden by native ownership' do
    get "#{base}/deals/#{private_deal.id}", headers: headers
    expect(response).to have_http_status(:not_found)

    post "#{base}/activities", headers: headers, params: payload.deep_merge(activity: { deal_id: private_deal.id }), as: :json

    expect(response).to have_http_status(:not_found)
    expect(JrcCrm::Activity.where(account: account, title: 'Synthetic bounded activity')).not_to exist
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_created')).not_to exist
  end

  it 'cannot create an activity for another owners hidden lead using a submitted source ID' do
    get "#{base}/leads/#{private_lead.id}", headers: headers
    expect(response).to have_http_status(:not_found)

    post "#{base}/activities", headers: headers,
                               params: payload.deep_merge(activity: { deal_id: nil, lead_id: private_lead.id }), as: :json

    expect(response).to have_http_status(:not_found)
    expect(JrcCrm::Activity.where(account: account, title: 'Synthetic bounded activity')).not_to exist
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_created')).not_to exist
  end

  it 'cannot reparent a currently visible activity to a hidden origin or record an edit audit' do
    activity = create(:jrc_crm_activity, account: account, user: actor, lead: own_lead, deal: nil)
    original = activity.attributes.deep_dup

    patch "#{base}/activities/#{activity.id}", headers: headers,
                                               params: { expected_version: activity.updated_at.utc.iso8601(6),
                                                         activity: { deal_id: private_deal.id, lead_id: nil, title: 'Must not change' } }, as: :json

    expect(response).to have_http_status(:not_found)
    expect(activity.reload.attributes).to eq(original)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'activity_updated')).not_to exist
  end

  it 'retains native corporate coverage even for an administrator creating through a source ID' do
    admin = create(:user, account: account, role: :administrator)
    company = account.master_companies.create!(name: 'Synthetic origin issuer', relationship_type: 'internal')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(operating_company: company, name: "Origin unit #{index}", code: "origin-#{index}")
    end
    account.jrc_crm_user_business_units.create!(user: admin, company: company, business_unit: units.first,
                                                scope: 'BUSINESS_UNIT', active: true, structure_managed: true)
    blocked = create(:jrc_crm_deal, account: account, owner: admin, metadata: { 'business_unit_id' => units.last.id }, pipeline: pipeline,
                                    stage: stage)
    admin_headers = admin.create_new_auth_token
    get "#{base}/deals/#{blocked.id}", headers: admin_headers
    expect(response).to have_http_status(:not_found)

    post "#{base}/activities", headers: admin_headers, params: payload.deep_merge(activity: { deal_id: blocked.id }), as: :json

    expect(response).to have_http_status(:not_found)
    expect(JrcCrm::Activity.where(account: account, title: 'Synthetic bounded activity')).not_to exist
  end

  it 'preserves creation against the actors own visible lead' do
    post "#{base}/activities", headers: headers,
                               params: payload.deep_merge(activity: { deal_id: nil, lead_id: own_lead.id }), as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('lead_id' => own_lead.id)
    expect(response.parsed_body.dig('user', 'id')).to eq(actor.id)
    expect(JrcCrm::Activity.find(response.parsed_body.fetch('id'))).to have_attributes(lead_id: own_lead.id, user_id: actor.id)
  end

  it 'preserves native administrator creation against another owners visible deal' do
    admin = create(:user, account: account, role: :administrator)
    post "#{base}/activities", headers: admin.create_new_auth_token, params: payload.deep_merge(activity: { deal_id: private_deal.id }), as: :json

    expect(response).to have_http_status(:created)
    expect(JrcCrm::Activity.find(response.parsed_body.fetch('id'))).to have_attributes(deal_id: private_deal.id, user_id: admin.id)
  end
end
