require 'rails_helper'

RSpec.describe 'Native portfolio destination input shapes', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:headers) { actor.create_new_auth_token }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  [false, [], {}].each do |value|
    it "rejects direct owner shape #{value.inspect} instead of unassigning or silently auditing a dropped field" do
      assignment
      expect do
        patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: value } }
      end.not_to change(JrcCrm::AuditEvent, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(assignment.reload.owner_id).to eq(actor.id)
    end

    it "rejects reviewed owner shape #{value.inspect} before creating a frozen proposal" do
      expect do
        post "#{base}/reviewed_batches", headers: headers, as: :json, params: {
          ids: [assignment.id], operation: 'assign', owner_id: value, request_id: SecureRandom.uuid
        }
      end.not_to change(JrcRelationship::BatchReview, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(assignment.reload.owner_id).to eq(actor.id)
    end

    it "rejects new portfolio owner shape #{value.inspect} before creating an unassigned customer allocation" do
      contact = create(:contact, account: account)
      expect do
        post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { contact_id: contact.id, owner_id: value } }
      end.not_to change(JrcRelationship::Assignment, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'retains current native scalar owner IDs during customer allocation creation' do
    contact = create(:contact, account: account)
    post "#{base}/portfolio", headers: headers, as: :json,
                              params: { assignment: { contact_id: contact.id, owner_id: actor.id.to_s } }
    expect(response).to have_http_status(:created)
    expect(JrcRelationship::Assignment.find(response.parsed_body.fetch('id'))).to have_attributes(account_id: account.id, owner_id: actor.id)
  end

  it 'retains explicit nil when creating an unassigned customer allocation' do
    contact = create(:contact, account: account)
    post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { contact_id: contact.id, owner_id: nil } }
    expect(response).to have_http_status(:created)
    expect(JrcRelationship::Assignment.find(response.parsed_body.fetch('id'))).to have_attributes(account_id: account.id, owner_id: nil)
  end
end
