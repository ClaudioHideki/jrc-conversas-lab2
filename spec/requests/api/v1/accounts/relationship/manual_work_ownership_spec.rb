require 'rails_helper'

RSpec.describe 'Relationship manual work ownership', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:action) do
    JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'manual',
                                    reason: 'Synthetic manual ownership', source_key: SecureRandom.uuid)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:headers) { actor.create_new_auth_token }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def change_owner(user)
    patch "#{base}/records/actions/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, owner_id: user.id,
      reason: 'Synthetic reviewed responsibility', due_at: 2.days.from_now.iso8601
    } }
  end

  it 'refuses an unauthenticated target without changing work, Agenda or audit' do
    target.update!(confirmed_at: nil)
    action
    expect { change_owner(target) }.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:forbidden)
    expect(action.reload.owner_id).to eq(actor.id)
    expect(action.activity_id).to be_nil
  end

  it 'refuses an authenticated account member outside the native portfolio scope' do
    target.account_users.find_by!(account: account).update!(role: :agent)
    change_owner(target)
    expect(response).to have_http_status(:not_found)
    expect(action.reload.owner_id).to eq(actor.id)
  end

  it 'keeps foreign account users outside the assignment boundary' do
    foreign = create(:user, account: create(:account), role: :administrator)
    change_owner(foreign)
    expect(response).to have_http_status(:not_found)
    expect(action.reload.owner_id).to eq(actor.id)
  end

  it 'refuses a view-only target even when the native team grants portfolio visibility' do
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team])
    target.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)
    team = create(:team, account: account)
    team.team_members.create!(user: target)
    assignment.update!(team: team)
    change_owner(target)
    expect(response).to have_http_status(:forbidden)
    expect(action.reload.owner_id).to eq(actor.id)
  end

  it 'rolls back an owner change when the target cannot read the native finance record' do
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    target.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)
    team = create(:team, account: account)
    team.team_members.create!(user: target)
    assignment.update!(team: team)
    action.update!(kind: 'finance')
    expect { change_owner(target) }.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:not_found)
    expect(action.reload).to have_attributes(owner_id: actor.id, reason: 'Synthetic manual ownership')
    expect(action.activity_id).to be_nil
  end

  it 'persists an authorized offline target and projects the same owner into the native Agenda' do
    target.account_users.find_by!(account: account).update!(availability: :offline)
    change_owner(target)
    expect(response).to have_http_status(:ok)
    expect(action.reload.owner_id).to eq(target.id)
    expect(action.activity.user_id).to eq(target.id)
    expect(assignment.reload.owner_id).to eq(actor.id)
  end

  it 'preserves native operating-unit boundaries for manual targets' do
    company = account.master_companies.create!(name: 'Synthetic manual ownership operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic owner unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    assignment.update!(business_unit: units.first)
    [[actor, units.first], [target, units.last]].each do |user, unit|
      account.jrc_crm_user_business_units.create!(user: user, scope: 'BUSINESS_UNIT', company: company,
                                                  business_unit: unit, active: true, structure_managed: true)
    end
    change_owner(target)
    expect(response).to have_http_status(:not_found)
    expect(action.reload.owner_id).to eq(actor.id)
  end

  it 'preserves an unchanged legacy inactive owner during an unrelated edit' do
    action.update!(owner: target)
    target.update!(confirmed_at: nil)
    change_owner(target)
    expect(response).to have_http_status(:ok)
    expect(action.reload).to have_attributes(owner_id: target.id, reason: 'Synthetic reviewed responsibility')
  end

  it 'returns assignment-specific working owners without filtering by online presence or configured capacity' do
    target.account_users.find_by!(account: account).update!(availability: :offline)
    inactive = create(:user, account: account, role: :administrator)
    inactive.update!(confirmed_at: nil)
    inaccessible = create(:user, account: account, role: :agent)
    get "#{base}/portfolio/#{assignment.id}/work_context", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.fetch('work_owners').map(&:first)
    expect(ids).to include(actor.id, target.id)
    expect(ids).not_to include(inactive.id, inaccessible.id)
  end
end
