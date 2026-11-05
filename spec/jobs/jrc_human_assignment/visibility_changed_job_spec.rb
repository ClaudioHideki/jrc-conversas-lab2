require 'rails_helper'

RSpec.describe JrcHumanAssignment::VisibilityChangedJob do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'publishes a content-free reset for current inbox members and administrators' do
    event = create_event
    expect do
      described_class.perform_now(event.id)
    end.to have_enqueued_job(ActionCableBroadcastJob).with(
      contain_exactly(agent.pubsub_token, admin.pubsub_token), 'conversation.access_reset', { account_id: account.id }
    )
  end

  it 'does not publish a reset for a rolled-back policy change' do
    expect do
      JrcHumanAssignmentPolicyEvent.transaction(requires_new: true) do
        create_event
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(described_class)
  end

  it 'ignores a missing event instead of broadcasting to another account' do
    expect { described_class.perform_now(-1) }.not_to have_enqueued_job(ActionCableBroadcastJob)
  end

  def create_event
    JrcHumanAssignmentPolicyEvent.create!(account: account, inbox: inbox, user: admin, previous_policy: {},
                                          next_policy: { 'visibility' => 'assigned_only', 'supervisor_ids' => [] })
  end
end
