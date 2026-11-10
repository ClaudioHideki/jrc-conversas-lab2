require 'rails_helper'

RSpec.describe JrcRelationship::WaitingReviewMonitor do
  let(:account) { create(:account) }
  let!(:manager) { create(:user, account: account, role: :administrator) }
  let!(:owner) { create(:user, account: account, role: :agent) }
  let!(:outsider) { create(:user, account: account, role: :agent) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: owner, contact: create(:contact, account: account)) }
  let(:action) do
    JrcRelationship::Action.create!(account: account, assignment: assignment, owner: owner, kind: 'manual', source_key: 'synthetic-review-notice',
                                    reason: 'Source action', status: 'waiting_customer', waiting_reason: 'Awaiting customer evidence',
                                    next_step: 'Review evidence', return_at: 1.hour.from_now)
  end
  let(:receipts) do
    JrcCrm::AuditEvent.where(account: account, resource_type: action.class.name, resource_id: action.id)
                      .where("metadata ->> 'action' = 'waiting_review_due'")
  end
  let(:notices) { Notification.where(account: account, primary_actor: action, notification_type: 'relationship_action') }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'records one durable overdue-review event and scoped native feed rows without changing the action or its clock' do
    original = action.reload.attributes.deep_dup
    travel_to(2.hours.from_now) do
      %w[UTC America/Sao_Paulo].each do |zone|
        Time.use_zone(zone) { described_class.new(account_id: account.id).call }
      end
      expect(notices.pluck(:user_id)).to contain_exactly(owner.id, manager.id)
      expect(receipts.count).to eq(1)
      expect(action.reload.attributes).to eq(original)
      expect(notices.pluck(:meta)).to all(include('relationship_event' => start_with('waiting_review_due:')))
    end
    expect(notices.where(user: outsider)).to be_empty
  end

  it 'notifies an overdue review through the existing SLA job even while the native SLA is paused' do
    policy = JrcOperations::SlaPolicy.create!(account: account, name: 'Waiting clock', scope_kind: 'relationship', total_minutes: 240,
                                              pause_statuses: ['waiting_customer'])
    action.update!(operations_sla_policy: policy)
    JrcOperations::SlaClock.new(action).start!.save!
    JrcOperations::SlaClock.new(action).status_changed!(from: 'open', to: 'waiting_customer')
    original = action.reload.sla_paused_at
    expect(original).to be_present
    travel_to(2.hours.from_now) do
      JrcRelationship::SlaMonitorJob.perform_now(account.id)
      expect(notices.count).to eq(2)
      expect(action.reload.sla_paused_at).to eq(original)
      expect(receipts.count).to eq(1)
    end
  end

  it 'does not notify a future review, a resolved action, a foreign account or a disabled account' do
    action
    described_class.new(account_id: account.id).call
    travel_to(2.hours.from_now) do
      described_class.new(account_id: create(:account).id).call
      account.disable_features!('jrc_relationship')
      described_class.new(account_id: account.id).call
      account.enable_features!('jrc_relationship')
      action.update!(status: 'dismissed')
      described_class.new(account_id: account.id).call
    end
    expect([notices.count, receipts.count]).to eq([0, 0])
  end

  it 'creates a new bounded notice for a genuinely rescheduled review without multiplying existing notification rows' do
    action
    travel_to(2.hours.from_now) do
      described_class.new(account_id: account.id).call
      notices.each { |notice| notice.update!(read_at: Time.current) }
      action.update!(return_at: 1.hour.from_now)
      described_class.new(account_id: account.id).call
      expect(receipts.count).to eq(1)
    end
    travel_to(4.hours.from_now) do
      2.times { described_class.new(account_id: account.id).call }
      expect([notices.count, receipts.count, notices.where(read_at: nil).count]).to eq([2, 2, 2])
    end
  end

  it 'rolls back a failed native notification projection and retries without recording a false successful notice' do
    action
    travel_to(2.hours.from_now) do
      allow(JrcRelationship::Notifications).to receive(:call).and_wrap_original do |original, source, **options|
        original.call(source, **options)
        raise ActiveRecord::StatementInvalid, 'Synthetic failure after native projection'
      end
      expect { described_class.new(account_id: account.id).call }.to raise_error(ActiveRecord::StatementInvalid)
      expect([notices.count, receipts.count]).to eq([0, 0])
      allow(JrcRelationship::Notifications).to receive(:call).and_call_original
      described_class.new(account_id: account.id).call
      expect([notices.count, receipts.count]).to eq([2, 1])
    end
  end

  it 'uses the current native source scope when reading a notice after portfolio access is revoked' do
    action
    travel_to(2.hours.from_now) { described_class.new(account_id: account.id).call }
    notice = notices.find_by!(user: owner)
    assignment.update!(owner: manager)
    expect(JrcRelationship::Notifications.visible?(notice)).to be(false)
    expect(NotificationFinder.new(owner, account).notifications).not_to include(notice)
    expect([NotificationFinder.new(owner, account).count, NotificationFinder.new(owner, account).unread_count]).to eq([0, 0])
    listener = ActionCableListener.instance
    allow(listener).to receive(:broadcast)
    listener.notification_created(Events::Base.new(:'notification.created', Time.current, notification: notice))
    listener.notification_updated(Events::Base.new(:'notification.updated', Time.current, notification: notice))
    expect(listener).not_to have_received(:broadcast)
    expect(NotificationFinder.new(manager, account).notifications.pluck(:id)).to include(notices.find_by!(user: manager).id)
  end
end
