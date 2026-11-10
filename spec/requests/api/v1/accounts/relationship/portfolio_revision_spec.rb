require 'rails_helper'

RSpec.describe 'Relationship optimistic portfolio edits', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/portfolio" }
  let(:version) { assignment.reload.updated_at.utc.iso8601(6) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'refuses an obsolete client revision atomically instead of overwriting a newer native change' do
    original = version
    assignment.update!(status: 'at_risk', updated_at: assignment.updated_at + 1.second)
    before = JrcCrm::AuditEvent.where(account: account).count
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: {
      owner_id: target.id, status: 'inactive', expected_version: original
    } }
    expect(response).to have_http_status(:conflict)
    expect(assignment.reload).to have_attributes(owner_id: actor.id, status: 'at_risk')
    expect(JrcCrm::AuditEvent.where(account: account).count).to eq(before)
  end

  it 'accepts the current revision without persisting its transport precondition as an attribute' do
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: {
      owner_id: target.id, expected_version: version
    } }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.owner_id).to eq(target.id)
    expect(response.parsed_body.fetch('assignment_version')).to eq(assignment.updated_at.utc.iso8601(6))
    event = JrcCrm::AuditEvent.where(account: account).for_resource(assignment.class.name, assignment.id).last
    expect(event.to_value).not_to have_key('expected_version')
  end

  it 'retains the established contract of callers that omit the optional precondition' do
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.owner_id).to eq(target.id)
  end

  it 'rejects malformed or explicitly empty preconditions instead of treating them as omitted' do
    [nil, '', 123, { value: version }].each do |value|
      patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: {
        owner_id: target.id, expected_version: value
      } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'does not use a known foreign revision to bypass native account isolation' do
    other = create(:account)
    user = create(:user, account: other)
    foreign = JrcRelationship::Assignment.create!(account: other, owner: user, contact: create(:contact, account: other))
    patch "#{base}/#{foreign.id}", headers: headers, as: :json, params: { assignment: {
      owner_id: target.id, expected_version: foreign.updated_at.utc.iso8601(6)
    } }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.owner_id).to eq(user.id)
  end
end
