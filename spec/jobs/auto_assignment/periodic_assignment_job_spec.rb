require 'rails_helper'

RSpec.describe AutoAssignment::PeriodicAssignmentJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:policy) { create(:assignment_policy, account: account) }

  before do
    account.enable_features!('assignment_v2')
    create(:inbox_assignment_policy, inbox: inbox, assignment_policy: policy)
  end

  it 'retries a persisted new-open request' do
    create(:conversation, account: account, inbox: inbox)
    expect(AutoAssignment::AssignmentJob).to receive(:enqueue_for_inbox).with(inbox.id)

    described_class.perform_now
  end

  it 'does not enqueue historical backlog or a policy activation alone' do
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.update_columns(auto_assignment_requested_at: nil)
    policy.update!(description: 'Explicit configuration change')
    expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)

    described_class.perform_now
  end

  it 'does not enqueue an inbox without a policy' do
    inbox.inbox_assignment_policy.destroy!
    create(:conversation, account: account, inbox: inbox)
    expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)

    described_class.perform_now
  end

  it 'does not enqueue disabled inboxes or policies' do
    create(:conversation, account: account, inbox: inbox)
    inbox.update!(enable_auto_assignment: false)
    expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)
    described_class.perform_now

    inbox.update!(enable_auto_assignment: true)
    policy.update!(enabled: false)
    described_class.perform_now
  end

  it 'does not enqueue accounts without Assignment V2' do
    create(:conversation, account: account, inbox: inbox)
    account.disable_features!('assignment_v2')
    expect(AutoAssignment::AssignmentJob).not_to receive(:enqueue_for_inbox)

    described_class.perform_now
  end
end
