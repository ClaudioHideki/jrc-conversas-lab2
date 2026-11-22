require 'rails_helper'

RSpec.describe 'Native scoped pause approval source', :approval_core do
  include_context 'with all-scope native pause approval'

  before { publish_all_pause_policies }

  it 'exposes only the reviewers own scope and opaque complete-context digest rather than other units or private justification' do
    row = create_reviewed_pause
    review = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id)
    first = review.scopes.order(:id).first
    snapshot = JrcApprovals::Catalog.snapshot(account: account, user: reviewers.first.user,
                                             key: 'contact_center.pause', resource_id: first.id)
    expect(snapshot.fetch('values').fetch('scope_unit_ids')).to eq([units.first.id.to_s])
    expect(snapshot.fetch('values').fetch('scope_unit_names')).to eq([units.first.name])
    expect(snapshot.fetch('values').fetch('unit_count')).to eq(1)
    expect(snapshot.fetch('values').fetch('context_digest')).to eq(review.context_digest)
    expect(snapshot.fetch('values')).not_to have_key('justification')
    expect(snapshot.fetch('values')).not_to have_key('units')
    expect(snapshot.fetch('values').to_json).not_to include(units.last.name)
  end

  it 'rejects source access and a vote by a reviewer covering only the other native business unit' do
    create_reviewed_pause
    first = pause_requests.first
    expect do
      JrcApprovals::Catalog.snapshot(account: account, user: reviewers.last.user, key: 'contact_center.pause', resource_id: first.resource_id)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect { approval_vote({ account: account }, reviewers.last, first) }.to raise_error(Pundit::NotAuthorizedError)
    expect(first.decisions).to be_empty
    expect(first.reload.state).to eq('pending')
  end

  it 'requires explicit Call Center approve independently of native Central decide and an ordinary administrator role' do
    create_reviewed_pause
    reviewer = reviewers.first
    reviewer.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_approvals_decide jrc_approvals_view_audit])
    expect { approval_vote({ account: account }, reviewer, pause_requests.first) }.to raise_error(Pundit::NotAuthorizedError)
    expect(pause_requests.first.decisions).to be_empty
    expect(pause_requests.first.reload.state).to eq('pending')
  end

  it 'does not allow a different operator to request approval for the original actors scope' do
    row = create_reviewed_pause
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    other_member = account.account_users.find_by!(user: other)
    permissions = %w[jrc_contact_center_view jrc_contact_center_operate jrc_approvals_request_create]
    other_member.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    account.jrc_crm_user_business_units.create!(user: other, scope: 'GROUP', active: true, structure_managed: true)
    scope = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id).scopes.first!
    expect do
      JrcApprovals::Requests.new(account: account, user: other).create!(key: 'contact_center.pause', resource_id: scope.id,
                                                                     idempotency_key: 'synthetic-forged-other-requester')
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(pause_requests.size).to eq(2)
  end

  it 'does not fallback to a formerly approved request when the latest request is pending' do
    row = create_reviewed_pause
    approve_pause_requests
    scope = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id).scopes.order(:id).first
    JrcApprovals::Requests.new(account: account, user: actor).create!(key: 'contact_center.pause', resource_id: scope.id,
                                                                   idempotency_key: 'synthetic-newer-pending-request')
    check = JrcContactCenter::PauseApprovalPolicyCheck.new(context: pause_context).call(scope_id: scope.id)
    expect(check.fetch(:status)).to eq('approval_required')
    expect(check.fetch(:approved_policy_version_ids)).to be_empty
    expect(apply_pause(row).state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end

RSpec.describe 'Native Central pause source serialization', :approval_core do
  include_context 'with all-scope native pause approval'

  it 'serializes only scoped immutable names and digests without exposing another company or the personal justification' do
    publish_all_pause_policies
    create_reviewed_pause
    row = JrcApprovals::RequestSerializer.new(pause_requests.first).as_json
    origin = row.fetch('origin')
    expect(origin).to include('kind' => 'contact_center_pause', 'own_scope_only' => true, 'historical' => true)
    expect(origin.fetch('scope_unit_ids')).to eq([units.first.id.to_s])
    expect(origin.fetch('scope_unit_names')).to eq([units.first.name])
    expect(origin.to_json).not_to include(units.last.name)
    expect(origin).not_to have_key('justification')
    expect(origin).not_to have_key('coverage')
    expect(origin.fetch('provider_confirmed')).to be(false)
  end
end
