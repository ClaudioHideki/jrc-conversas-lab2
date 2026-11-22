require 'rails_helper'

RSpec.describe JrcContactCenter::PauseApprovalPolicyCheck, :approval_core do
  include_context 'with all-scope native pause approval'

  def conflicting_policy
    business = businesses.first
    service = JrcApprovals::Policies.new(account: account, user: policy_author.user)
    policy = service.create!(code: 'SYNTHETIC_PAUSE_CONFLICT', name: 'SYNTHETIC equal-priority conflict',
                             module_key: 'contact_center', event_key: 'pause', issuer_company_id: business.company_id,
                             business_unit_id: business.id, definition: approval_definition([reviewers.first]))
    service.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    [service, policy.reload]
  end

  it 'rejects a real conflicting publication before it can replace a usable scoped policy or affect a pending pause' do
    publish_all_pause_policies
    row = create_reviewed_pause
    service, policy = conflicting_policy
    original = policy.attributes.deep_dup
    expect do
      service.publish!(policy_id: policy.id, expected_version: policy.lock_version)
    end.to raise_error(JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT')
    expect(policy.reload.attributes).to eq(original)
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  # Explicit fault injection at the selector boundary, not a claim that native publishing permits the conflicting policy.
  it 'propagates a simulated selector conflict rather than treating it as missing or ready', :simulated_selection_failure do
    publish_all_pause_policies
    row = create_reviewed_pause
    scope = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id).scopes.first!
    error = JrcApprovals::Error.new('POLICY_SELECTION_CONFLICT')
    allow(JrcApprovals::Selection).to receive(:call).and_raise(error)
    expect do
      described_class.new(context: pause_context).call(scope_id: scope.id)
    end.to raise_error(JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT')
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end
