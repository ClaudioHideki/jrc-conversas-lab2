require 'rails_helper'

RSpec.describe 'Native legacy batch owner input', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/portfolio/batch" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  [false, true, 1.5, 0, 'invalid', {}].each do |owner|
    it "rejects malformed owner #{owner.inspect} without unassigning or mutating a customer" do
      assignment
      expect do
        post base, headers: headers, as: :json, params: {
          ids: [assignment.id], operation: 'assign', owner_id: owner, request_id: SecureRandom.uuid
        }
      end.not_to change(JrcCrm::AuditEvent, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(assignment.reload.owner_id).to eq(actor.id)
    end
  end

  it 'rejects arrays instead of using Active Record multi-find as a recipient' do
    post base, headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: [target.id], request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'retains native scalar string recipients and explicit nil unassignment' do
    post base, headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: target.id.to_s, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('updated' => 1)
    expect(assignment.reload.owner_id).to eq(target.id)
    post base, headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: nil, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.owner_id).to be_nil
  end
end
