require 'rails_helper'

RSpec.describe 'Native portfolio destination access', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rejects an inactive destination without changing the root, delegated work or audit when no capacity rule exists' do
    action = assignment.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Synthetic pending work',
                                        source_key: SecureRandom.uuid)
    target.update!(confirmed_at: nil)
    expect do
      patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    end.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:forbidden)
    expect([assignment.reload.owner_id, action.reload.owner_id]).to eq([actor.id, actor.id])
  end

  it 'rejects a current account member without native Relationship access' do
    role = account.custom_roles.create!(name: 'Synthetic directory only', permissions: ['contact_manage'])
    target.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:forbidden)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'refuses a destination outside the native operating unit even when its role is administrator' do
    company = account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |i|
      account.jrc_crm_business_units.create!(company_id: company.id, name: "Synthetic unit #{i}", code: SecureRandom.hex(6))
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: units.first,
                                                active: true, structure_managed: true)
    account.jrc_crm_user_business_units.create!(user: target, scope: 'BUSINESS_UNIT', company: company, business_unit: units.last,
                                                active: true, structure_managed: true)
    assignment.update!(business_unit: units.first)
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:forbidden)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'rejects an inactive destination before persisting a new executable reviewed proposal' do
    target.update!(confirmed_at: nil)
    assignment
    expect do
      post "#{base}/reviewed_batches", headers: headers, as: :json, params: {
        ids: [assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid
      }
    end.not_to change(JrcRelationship::BatchReview, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'requires native manage permission to create a portfolio row as well as team permission' do
    role = account.custom_roles.create!(name: 'Synthetic team viewer', permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team])
    actor.account_users.find_by!(account: account).update!(custom_role: role)
    contact = create(:contact, account: account)
    expect do
      post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { contact_id: contact.id, owner_id: actor.id } }
    end.not_to change(JrcRelationship::Assignment, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'refuses an initial allocation to an inactive target and rolls back the newly created row' do
    target.update!(confirmed_at: nil)
    contact = create(:contact, account: account)
    expect do
      post "#{base}/portfolio", headers: headers, as: :json, params: { assignment: { contact_id: contact.id, owner_id: target.id } }
    end.not_to change(JrcRelationship::Assignment, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'allows a native agent to receive its future owned row without requiring access to the previous owner portfolio' do
    target.account_users.find_by!(account: account).update!(role: :agent)
    target_context = JrcRelationship::Context.new(target.account_users.find_by!(account: account))
    expect(target_context.assignments.exists?(id: assignment.id)).to be(false)
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:ok)
    expect(JrcRelationship::Context.new(target_context.member).assignments.exists?(id: assignment.id)).to be(true)
  end

  it 'uses the same destination authority for the legacy batch API without weakening unchanged historical owner edits' do
    assignment
    target.update!(confirmed_at: nil)
    post "#{base}/portfolio/batch", headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:forbidden)
    expect(assignment.reload.owner_id).to eq(actor.id)
    target.update!(confirmed_at: Time.current)
    assignment.update!(owner: target)
    action = assignment.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Synthetic delegated work',
                                        source_key: SecureRandom.uuid)
    target.update!(confirmed_at: nil)
    post "#{base}/portfolio/batch", headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: target.id.to_s, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:ok)
    expect(action.reload.owner_id).to eq(actor.id)
  end

  it 'preserves native access-only portfolio admission without granting manage permission to the recipient' do
    role = account.custom_roles.create!(name: 'Synthetic portfolio viewer', permissions: %w[contact_manage jrc_relationship_view])
    target_member = target.account_users.find_by!(account: account)
    target_member.update!(role: :agent, custom_role: role)
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:ok)
    current = JrcRelationship::Context.new(target_member)
    expect(current.assignments.exists?(id: assignment.id)).to be(true)
    expect(current.policy.manage?).to be(false)
  end
end
