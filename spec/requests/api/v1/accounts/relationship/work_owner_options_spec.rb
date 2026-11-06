require 'rails_helper'

RSpec.describe 'Relationship record-specific owner choices', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:record) do
    JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'finance',
                                    reason: 'Synthetic restricted work', source_key: SecureRandom.uuid)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/portfolio/#{assignment.id}/work_context" }
  let(:headers) { actor.create_new_auth_token }
  let(:hint) { { work_kind: 'actions', work_record_id: record.id } }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    target.account_users.find_by!(account: account).update!(custom_role: role)
    team = create(:team, account: account)
    team.team_members.create!(user: target)
    assignment.update!(team: team)
  end

  it 'omits destinations unable to read the existing record even when they can work on the portfolio' do
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('work_owners').map(&:first)).to include(target.id)
    get url, headers: headers, params: hint, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('work_owners').map(&:first)).to include(actor.id)
    expect(response.parsed_body.fetch('work_owners').map(&:first)).not_to include(target.id)
    expect(record.reload.owner_id).to eq(actor.id)
  end

  it 'does not accept a record from a different portfolio as owner-selection context' do
    other = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    record.update!(assignment: other)
    get url, headers: headers, params: hint, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('work_owners')
  end

  it 'does not resolve a foreign-account record through supplied kind and ID' do
    foreign = create(:account)
    user = create(:user, account: foreign, role: :administrator)
    portfolio = JrcRelationship::Assignment.create!(account: foreign, owner: user, contact: create(:contact, account: foreign))
    work = JrcRelationship::Action.create!(account: foreign, assignment: portfolio, owner: user, kind: 'manual',
                                           reason: 'Synthetic foreign work', source_key: SecureRandom.uuid)
    get url, headers: headers, params: { work_kind: 'actions', work_record_id: work.id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Synthetic foreign work', 'work_owners')
  end

  it 'rejects incomplete and unsupported hints without resolving arbitrary model names' do
    [{ work_kind: 'actions' }, { work_record_id: record.id }, { work_kind: 'User', work_record_id: actor.id },
     { work_kind: 'actions', work_record_id: [record.id] }, { work_kind: 'actions', work_record_id: 0 }].each do |params|
      get url, headers: headers, params: params, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
