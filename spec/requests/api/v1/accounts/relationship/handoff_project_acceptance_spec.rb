require 'rails_helper'

RSpec.describe 'Native CS handoff from project completion', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: contact, owner: actor) }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: actor, contact: contact, key: 'CS_TEST',
                                 name: 'Synthetic implementation', status: 'completed')
  end
  let(:handoff) do
    JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: project.class.name, source_id: project.id)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/handoffs/#{handoff.id}/decide" }
  let(:headers) { actor.create_new_auth_token }
  let(:checklist) { %w[contract products contacts objectives promises pending_items].index_with(true) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_projects') }

  it 'revalidates completion at acceptance and rolls back a decision on a reopened native implementation' do
    handoff
    project.update!(status: 'active')
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Source was reopened', checklist: checklist }
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'accepts a currently completed native implementation with the complete checklist and real decision actor' do
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Implementation reviewed', checklist: checklist }
    expect(response).to have_http_status(:ok), response.body
    expect(handoff.reload).to have_attributes(status: 'accepted', decided_by_id: actor.id, checklist: checklist)
  end

  it 'allows a reasoned rejection after reopening without falsely accepting the delivery' do
    handoff
    project.update!(status: 'active')
    post url, headers: headers, as: :json, params: { status: 'rejected', reason: 'Implementation incomplete', checklist: { contract: false } }
    expect(response).to have_http_status(:ok), response.body
    expect(handoff.reload).to have_attributes(status: 'rejected', reason: 'Implementation incomplete')
  end

  it 'does not accept or disclose a legacy case referencing a foreign project' do
    other = create(:account)
    foreign = JrcProjects::Project.create!(account: other, owner: create(:user, account: other), key: 'CS_FOREIGN', name: 'Foreign synthetic source')
    handoff.update!(source_id: foreign.id)
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Forged source', checklist: checklist }
    expect(response).to have_http_status(:not_found)
    expect(handoff.reload.attributes).to eq(before)
  end
end
