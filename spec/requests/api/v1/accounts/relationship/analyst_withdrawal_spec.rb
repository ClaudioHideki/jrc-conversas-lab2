require 'rails_helper'

RSpec.describe 'Governed Relationship-only analyst withdrawal', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: analyst) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:url) { "#{base}/team/#{analyst.id}/withdraw" }
  let(:digest) do
    get "#{base}/team/#{analyst.id}/withdrawal_readiness", headers: headers
    response.parsed_body.fetch('snapshot_digest')
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'finalizes only Relationship eligibility with a fresh zero-workload review and an audited reason' do
    team = create(:team, account: account)
    team.team_members.create!(user: analyst)
    expected = digest
    before = [User.count, AccountUser.count, TeamMember.count, member.attributes.except('updated_at')]
    post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: expected, reason: 'Synthetic approved CS withdrawal' } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'withdrawn', 'scope' => 'relationship', 'analyst_id' => analyst.id)
    expect([member.reload.jrc_relationship_withdrawn_at.present?, member.jrc_relationship_eligibility_version]).to eq([true, 1])
    expect([User.count, AccountUser.count, TeamMember.count]).to eq(before.first(3))
    expect(member.attributes.except('updated_at', 'jrc_relationship_withdrawn_at', 'jrc_relationship_eligibility_version')).to eq(
      before.last.except('jrc_relationship_withdrawn_at', 'jrc_relationship_eligibility_version')
    )
    event = JrcCrm::AuditEvent.where(account: account).for_resource('AccountUser', member.id).last!
    expect(event.actor_id).to eq(actor.id)
    expect(event.to_value).to include('scope' => 'relationship', 'snapshot_digest' => expected, 'reason' => 'Synthetic approved CS withdrawal')
  end

  it 'denies Relationship endpoints after withdrawal while retaining the native Customer Directory permission' do
    post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: digest, reason: 'Synthetic scoped withdrawal' } }
    member.reload
    expect(JrcCustomers::DirectoryPolicy.new({ account: account, account_user: member, user: analyst }, :directory).access?).to be(true)
    get "#{base}/metadata", headers: analyst.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects a stale review after new pending work and changes no membership, owner or audit' do
    expected = digest
    assignment = JrcRelationship::Assignment.create!(account: account, owner: analyst, contact: create(:contact, account: account))
    expect do
      post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: expected, reason: 'Synthetic stale review' } }
    end.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:conflict)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
    expect(assignment.reload.owner_id).to eq(analyst.id)
  end

  it 'refuses pending nested obligations even when their current digest is supplied' do
    assignment = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic pending plan',
                                         goals: [{ 'metric' => 'Delivery', 'owner_id' => analyst.id }])
    post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: digest, reason: 'Synthetic incomplete handoff' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'requires a bounded reason and digest and prevents self-withdrawal' do
    expected = digest
    [nil, '', 'x' * 4001, {}].each do |reason|
      post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: expected, reason: reason } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    post "#{base}/team/#{actor.id}/withdraw", headers: headers, as: :json,
                                              params: { withdrawal: { snapshot_digest: expected, reason: 'Synthetic self withdrawal' } }
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not let a foreign account act or forge the acting user through request fields' do
    foreign = create(:user, account: create(:account), role: :administrator)
    expected = digest
    post url, headers: foreign.create_new_auth_token, as: :json,
              params: { withdrawal: { snapshot_digest: expected, reason: 'Synthetic foreign attempt', actor_id: actor.id, account_id: account.id } }
    expect(response).to have_http_status(:forbidden)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'does not duplicate the audit or move the timestamp when a successful withdrawal is retried' do
    attrs = { withdrawal: { snapshot_digest: digest, reason: 'Synthetic confirmed withdrawal' } }
    post url, headers: headers, as: :json, params: attrs
    expect(response).to have_http_status(:ok)
    stamp = member.reload.jrc_relationship_withdrawn_at
    expect { post url, headers: headers, as: :json, params: attrs }.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:ok)
    expect(member.reload.jrc_relationship_withdrawn_at).to eq(stamp)
  end

  it 'requires native configure permission even for a manager who can inspect the complete review' do
    role = account.custom_roles.create!(name: 'Synthetic team reviewer',
                                        permissions: %w[jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    actor.account_users.find_by!(account: account).update!(custom_role: role)
    expected = digest
    expect(response.parsed_body.fetch('can_withdraw_relationship')).to be(false)
    post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: expected, reason: 'Synthetic unauthorized withdrawal' } }
    expect(response).to have_http_status(:forbidden)
    expect(member.reload.jrc_relationship_withdrawn_at).to be_nil
  end

  it 'requires native review of active survey execution policies before withdrawal and prevents their reactivation afterward' do
    questions = [{ 'key' => 'rating', 'text' => 'Synthetic rating', 'type' => 'scale', 'min' => 0, 'max' => 10, 'required' => true }]
    definition = JrcRelationship::SurveyDefinition.create!(account: account, name: 'Synthetic NPS', code: SecureRandom.hex(8), kind: 'nps',
                                                           status: 'active', questions: questions)
    rule = JrcRelationship::SurveyRule.create!(account: account, definition: definition, name: 'Synthetic active execution',
                                               execution_member: member, active: true, matchers: { 'source_type' => 'Conversation' })
    expected = digest
    expect(response.parsed_body.fetch('counts')).to include('survey_rules' => 1)
    post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: expected, reason: 'Synthetic rule still active' } }
    expect(response).to have_http_status(:unprocessable_entity)
    context = JrcRelationship::Context.new(actor.account_users.find_by!(account: account))
    JrcRelationship::SurveyAdministration.new(context).save(kind: 'rules', id: rule.id, expected_version: rule.version,
                                                            attributes: { active: false })
    get "#{base}/team/#{analyst.id}/withdrawal_readiness", headers: headers
    fresh_digest = response.parsed_body.fetch('snapshot_digest')
    expect(response.parsed_body).to include('can_withdraw_relationship' => true, 'counts' => hash_including('survey_rules' => 0))
    post url, headers: headers, as: :json, params: { withdrawal: { snapshot_digest: fresh_digest, reason: 'Synthetic policy reviewed and disabled' } }
    expect(response).to have_http_status(:ok)
    expect { rule.reload.update!(active: true) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(rule.reload.active).to be(false)
    missing = rule.dup
    missing.assign_attributes(execution_member_id: -1, active: true)
    expect { missing.save! }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
