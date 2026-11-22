require 'rails_helper'

RSpec.describe JrcContactCenter::DeferredPauseManager, 'all-scope native approval', :approval_core do
  include_context 'with all-scope native pause approval'

  it 'creates every scope in the native Central atomically without applying a pause or pretending a provider ACK' do
    publish_all_pause_policies
    before = member.reload.availability
    row = create_reviewed_pause
    review = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id)
    expect(row.state).to eq('pending')
    expect(review.scopes.count).to eq(2)
    expect(pause_requests.map(&:business_unit_id)).to eq(businesses.map(&:id))
    expect(pause_requests.map(&:state)).to eq(%w[pending pending])
    expect(member.reload.availability).to eq(before)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    expect(pause_requests.map(&:resource_type)).to all(eq('JrcContactCenter::PauseApprovalScope'))
  end

  it 'rejects empty policy selection without leaving any canonical intent, scope or partial request behind' do
    expect { create_reviewed_pause }.to raise_error(JrcContactCenter::OperationError, 'pause_approval_policy_missing')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalScope.where(account: account)).to be_empty
    expect(pause_requests).to be_empty
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'rolls back the complete creation when only the first affected company has a policy' do
    publish_pause_policy(0)
    expect { create_reviewed_pause }.to raise_error(JrcContactCenter::OperationError, 'pause_approval_policy_missing')
    expect(pause_requests).to be_empty
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
  end

  it 'rolls back both scopes if the last native plan has no currently eligible approver' do
    publish_all_pause_policies
    reviewers.last.custom_role.update!(permissions: [])
    expect { create_reviewed_pause }.to raise_error(JrcApprovals::Error)
    expect(pause_requests).to be_empty
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
  end

  it 'requires an explicit complete impact revision outside the unchanged historical input fields' do
    publish_all_pause_policies
    expect { manager.request!(values) }.to raise_error(JrcContactCenter::OperationError, 'pause_approval_review_required')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(pause_requests).to be_empty
  end

  it 'does not accept an impact reviewed before a real membership change' do
    publish_all_pause_policies
    preview = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(values)
    JrcContactCenter::QueueMembership.find_by!(account: account, account_user: member, queue: queues.last).update!(active: false)
    expect do
      manager.request_reviewed!(values, expected_approval_digest: preview.fetch('digest'))
    end.to raise_error(JrcContactCenter::OperationError, 'pause_approval_review_required')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(pause_requests).to be_empty
  end

  it 'does not consume a single approved scope as if it covered both affected companies' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approval_vote({ account: account }, reviewers.first, pause_requests.first)
    expect(apply_pause(row).state).to eq('pending')
    expect(pause_requests.map(&:state)).to eq(%w[approved pending])
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalReadiness.new(account: account, member: member).call(row).fetch(:status)).to eq('approval_required')
  end

  it 'applies only after every native decision and preserves the complete immutable source and local-only event receipts' do
    publish_all_pause_policies
    row = create_reviewed_pause
    review = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id)
    original = review.attributes.deep_dup
    approve_pause_requests
    expect(apply_pause(row).state).to eq('applied')
    event = JrcContactCenter::AgentStateEvent.where(account: account, account_user: member).sole
    expect(event.state).to eq('paused')
    expect(event.metadata).to include('provider_confirmed' => false, 'pause_approval_context_digest' => review.context_digest)
    expect(event.metadata.fetch('pause_approval_scope_ids')).to eq(review.scopes.order(:id).map { |scope| scope.id.to_s })
    expect(review.reload.attributes).to eq(original)
    expect(pause_requests.map(&:state)).to eq(%w[approved approved])
  end

  it 'preserves an applied native receipt during retries without another paused event or another approval request' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    apply_pause(row)
    original = row.reload.attributes.deep_dup
    retry_result = manager.apply!(request_id: row.request_id, expected_state_version: '0')
    expect(retry_result.attributes).to eq(original)
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
    expect(pause_requests.size).to eq(2)
    expect(manager.request_reviewed!(values, expected_approval_digest: 'f' * 64).id).to eq(row.id)
  end

  it 'also denies a direct native paused transition when no approved canonical request exists' do
    expect do
      JrcContactCenter::AgentStateManager.new(account: account, account_user: member).transition(
        state: 'paused', reason_code: definition.fetch('code'), command_id: SecureRandom.uuid, expected_state_version: '0'
      )
    end.to raise_error(JrcContactCenter::OperationError, 'pause_approval_required')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    expect(pause_requests).to be_empty
  end

  it 'does not apply after approved requests expire' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    travel_to(pause_requests.map(&:expires_at).max + 1.second) do
      expect(apply_pause(row).state).to eq('pending')
      expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    end
  end

  it 'reauthorizes the operator after decisions instead of treating historical approval as a live permission' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_approvals_request_create])
    expect { apply_pause(row) }.to raise_error(Pundit::NotAuthorizedError)
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'requires review after actual scope impact changes without extending old approvals or modifying the immutable capture' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    review = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id)
    original = review.payload.deep_dup
    JrcContactCenter::QueueMembership.find_by!(account: account, account_user: member, queue: queues.last).update!(active: false)
    expect(apply_pause(row)).to have_attributes(state: 'blocked', failure_code: 'pause_request_review_required')
    expect(review.reload.payload).to eq(original)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'does not let another account apply an owned request UUID' do
    publish_all_pause_policies
    row = create_reviewed_pause
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    user = create(:user, :contact_center_eligible, account: foreign, role: :agent)
    other = JrcContactCenter::DeferredPauseManager.new(account: foreign, member: foreign.account_users.find_by!(user: user))
    expect { other.apply!(request_id: row.request_id, expected_state_version: '0') }.to raise_error(ActiveRecord::RecordNotFound)
    expect(row.reload.state).to eq('pending')
    expect(JrcContactCenter::AgentStateEvent.where(account: foreign)).to be_empty
  end

  it 'keeps rejected scope evidence from authorizing any effective pause' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approval_vote({ account: account }, reviewers.first, pause_requests.first, decision: 'rejected')
    approval_vote({ account: account }, reviewers.last, pause_requests.last)
    expect(apply_pause(row).state).to eq('pending')
    expect(pause_requests.map(&:state)).to eq(%w[rejected approved])
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'preserves cancellation history and makes the origin unverifiable instead of sending or applying an approval' do
    publish_all_pause_policies
    row = create_reviewed_pause
    review = JrcContactCenter::PauseApprovalReview.find_by!(account: account, deferred_pause_request_id: row.id)
    original = review.payload.deep_dup
    manager.cancel!(row.request_id)
    expect(JrcContactCenter::PauseApprovalSourceCurrent.new(review).call).to eq('current' => false, 'digest' => 'unavailable')
    expect(review.reload.payload).to eq(original)
    expect(row.reload.state).to eq('cancelled')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
    expect { approval_vote({ account: account }, reviewers.first, pause_requests.first) }.to raise_error(JrcApprovals::Error, 'CONTEXT_STALE')
  end
end
