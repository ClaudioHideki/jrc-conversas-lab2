require 'rails_helper'

RSpec.describe 'Call Center explicit access authorizations', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { actor.create_new_auth_token }
  let(:actor_link) { account.account_users.find_by!(user: actor) }
  let(:actor_role) { create(:custom_role, account: account, permissions: JrcContactCenter::ModulePolicy::PERMISSIONS) }
  let(:recipient) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: recipient) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/access_authorizations" }
  let(:service) { JrcContactCenter::AccessAuthorization.new(context: { account: account, account_user: actor_link, user: actor }) }
  let(:grant) { service.grant_for(member) }
  let(:revision) { service.revision(member, grant) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    actor_link.update!(custom_role: actor_role)
  end

  it 'lists native users with bounded pagination and explicit pending state' do
    member
    get "#{base}/users", headers: headers, params: { page: 1, per_page: 1 }
    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data['items'].size).to eq(1)
    expect(data['meta']['total']).to eq(2)
    get "#{base}/users/#{member.id}", headers: headers
    expect(response.parsed_body['item']).to include('eligible' => false, 'effective' => [])
  end

  it 'persists eligibility and individual rights, then denies access again after suspension' do
    attributes = { authorization: { eligible: true, allowed: ['jrc_contact_center_view'] }, expected_revision: revision }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    data = response.parsed_body['item']
    expect(data['effective']).to include('jrc_contact_center_view')
    attributes = { authorization: { eligible: false }, expected_revision: data['revision'] }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::AccessGrant.find_by!(account_user: member).eligible).to be(false)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/administration", headers: recipient.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not let an administrator grant a critical power above their own authority' do
    actor_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    attributes = { authorization: { eligible: true, allowed: ['jrc_contact_center_publish'] }, expected_revision: revision }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: member)).to be(false)
  end

  it 'cannot authorize itself by persisting a grant before checking the actor' do
    actor_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    own = service.grant_for(actor_link)
    expected = service.revision(actor_link, own)
    attributes = { authorization: { allowed: ['jrc_contact_center_publish'] }, expected_revision: expected }
    patch "#{base}/users/#{actor_link.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(own.reload.allowed).not_to include('jrc_contact_center_publish')
  end

  it 'treats removing an individual denial as a grant requiring actor authority' do
    actor_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    target_role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_publish])
    member.update!(custom_role: target_role)
    grant.assign_attributes(eligible: true, denied: ['jrc_contact_center_publish'])
    grant.save!
    attributes = { authorization: { denied: [] }, expected_revision: service.revision(member, grant) }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(grant.reload.denied).to eq(['jrc_contact_center_publish'])
  end

  it 'rejects a stale revision and missing revision without overwriting state' do
    old = revision
    JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: false)
    patch "#{base}/users/#{member.id}", headers: headers, params: { authorization: { eligible: true }, expected_revision: old }, as: :json
    expect(response).to have_http_status(:conflict)
    patch "#{base}/users/#{member.id}", headers: headers, params: { authorization: { eligible: true } }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(JrcContactCenter::AccessGrant.find_by!(account_user: member).eligible).to be(false)
  end

  it 'does not grant corporate coverage when eligibility is activated' do
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    JrcCrm::UserBusinessUnit.create!(
      account: account, user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: unit, active: true, structure_managed: true
    )
    attributes = { authorization: { eligible: true }, expected_revision: revision }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: member)).to be(false)
    expect(JrcCrm::UserBusinessUnit.where(account: account, user: recipient)).to be_empty
  end

  it 'does not allow an ordinary eligible agent to manage grants' do
    actor_link.update!(role: :agent)
    get "#{base}/users", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns not found for a native member from another account' do
    foreign = create(:user, account: create(:account))
    foreign_link = foreign.account_users.first
    get "#{base}/users/#{foreign_link.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'preserves an audit with actor and correlation and rolls it back on a refused grant' do
    attributes = { authorization: { eligible: true }, expected_revision: revision }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    row = Audited.audit_class.where(comment: JrcContactCenter::ConfigurationAudit::AUTHORITY_COMMENT, associated: account).last
    expect(row.user_id).to eq(actor.id)
    expect(row.request_uuid).to be_present
    expect(row.audited_changes.dig('attributes', 1, 'eligible')).to be(true)
    actor_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
    count = Audited.audit_class.where(comment: JrcContactCenter::ConfigurationAudit::AUTHORITY_COMMENT, associated: account).count
    attributes = { authorization: { allowed: ['jrc_contact_center_publish'] }, expected_revision: response.parsed_body['item']['revision'] }
    patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
    expect(Audited.audit_class.where(comment: JrcContactCenter::ConfigurationAudit::AUTHORITY_COMMENT, associated: account).count).to eq(count)
  end

  it 'returns named origins only in an authorized detail without activating the recipient' do
    team = create(:team, account: account)
    team.add_members([recipient.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_monitor'])
    expect { get "#{base}/users/#{member.id}", headers: headers }.not_to change(JrcContactCenter::AccessGrant, :count)
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item.dig('origins', 'teams')).to eq([{ 'id' => team.id, 'name' => team.name, 'permissions' => ['jrc_contact_center_monitor'] }])
    expect(item.values_at('eligible', 'effective')).to eq([false, []])
    get "#{base}/users", headers: headers
    expect(response.parsed_body.fetch('items').flat_map(&:keys)).not_to include('origins')
  end

  [true, 'true', 1].each do |value|
    it "rejects a malformed individual array #{value.inspect}" do
      attributes = { authorization: { allowed: value }, expected_revision: revision }
      patch "#{base}/users/#{member.id}", headers: headers, params: attributes, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::AccessGrant.exists?(account_user: member)).to be(false)
    end
  end

  it 'refuses a cached actor after native authentication is withdrawn before an authorization write' do
    expected = revision
    expect(actor.confirmed?).to be(true)
    User.find(actor.id).update!(confirmed_at: nil)
    expect(actor.confirmed?).to be(true)
    expect do
      service.update!(subject: member, attributes: { eligible: true, allowed: ['jrc_contact_center_view'] }, expected: expected)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: member)).to be(false)
    expect(actor.reload.active_for_authentication?).to be(false)
  end
end
