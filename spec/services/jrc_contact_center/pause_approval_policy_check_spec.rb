require 'rails_helper'

RSpec.describe JrcContactCenter::PauseApprovalPolicyCheck, :approval_core do
  include_context 'with all-scope native pause approval'

  it 'propagates a real native policy-selection conflict rather than treating it as missing or ready' do
    publish_all_pause_policies
    row = create_reviewed_pause
    scope = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id).scopes.first!
    business = businesses.first
    service = JrcApprovals::Policies.new(account: account, user: policy_author.user)
    policy = service.create!(code: 'SYNTHETIC_PAUSE_CONFLICT', name: 'SYNTHETIC equal-priority conflict',
                             module_key: 'contact_center', event_key: 'pause', issuer_company_id: business.company_id,
                             business_unit_id: business.id, definition: approval_definition([reviewers.first]))
    service.validate!(policy_id: policy.id, expected_version: policy.lock_version)
    service.publish!(policy_id: policy.id, expected_version: policy.reload.lock_version)
    expect do
      described_class.new(context: pause_context).call(scope_id: scope.id)
    end.to raise_error(JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT')
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end
end
