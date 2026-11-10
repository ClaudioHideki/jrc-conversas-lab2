require 'rails_helper'

RSpec.describe 'Durable native approval notifications', :approval_core, type: :model do
  self.use_transactional_tests = false
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope) }
  let(:approver) { approval_actor(scope) }
  let(:rule) { approval_publish(scope, author, approval_definition([approver]).merge('delegation_allowed' => true)) }
  let(:request) do
    rule
    approval_request(scope, author)
  end
  let(:event) { JrcApprovals::AuditEvent.find_by!(request_id: request.id, event_type: 'request_created') }

  it 'persists the outbox in the domain transaction without enqueuing delivery from the approval API path' do
    clear_enqueued_jobs
    event
    expect(JrcApprovals::NotificationOutbox.where(account: scope[:account], source_event: event).count).to eq(1)
    expect(Notification.where(account: scope[:account], notification_type: 'approval_event')).to be_empty
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(JrcApprovals::NotificationProjectionJob)
  end

  it 'rolls back new requests, audit and outbox together on a domain rollback' do
    rule
    before = [JrcApprovals::Request.where(account: scope[:account]).count, JrcApprovals::AuditEvent.where(account: scope[:account]).count,
              JrcApprovals::NotificationOutbox.where(account: scope[:account]).count]
    JrcApprovals::Request.transaction do
      approval_request(scope, author)
      raise ActiveRecord::Rollback
    end
    expect([JrcApprovals::Request.where(account: scope[:account]).count, JrcApprovals::AuditEvent.where(account: scope[:account]).count,
            JrcApprovals::NotificationOutbox.where(account: scope[:account]).count]).to eq(before)
  end

  it 'projects one native in-app row with bounded data and no push or email job' do
    clear_enqueued_jobs
    JrcApprovals::NotificationProjection.new(event.id).call
    notice = Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: request, notification_type: 'approval_event')
    expect(JrcApprovals::NotificationOutbox.find_by!(source_event: event).completed_at).to be_present
    expect(notice.push_event_data).to include(
      'primary_actor' => { id: request.id, account_id: scope[:account].id, meta: {} },
      'user' => { id: approver.user_id }, 'meta' => { 'approval_event' => 'request_created', 'approval_target' => 'inbox' }
    )
    expect(notice.push_event_data.to_json).not_to include('snapshot', 'test_amount', 'fingerprint', 'pubsub_token', approver.user.email)
    expect(enqueued_jobs.map { |job| job[:job] }).not_to include(Notification::EmailNotificationJob, Notification::PushNotificationJob)
  end

  it 'does not duplicate or reset a read notification when replaying a completed source' do
    JrcApprovals::NotificationProjection.new(event.id).call
    notice = Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: request)
    notice.update!(read_at: Time.current)
    read_at = notice.reload.read_at
    JrcApprovals::NotificationProjection.new(event.id).call
    expect(Notification.where(account: scope[:account], user: approver.user, primary_actor: request).count).to eq(1)
    expect(notice.reload.read_at).to eq(read_at)
  end

  it 'recovers after a post-commit dispatcher failure without changing the committed approval or duplicating a row' do
    source = event
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_raise(StandardError, 'Synthetic dispatcher unavailable')
    expect { JrcApprovals::NotificationProjection.new(source.id).call }.to raise_error(StandardError, 'Synthetic dispatcher unavailable')
    expect(request.reload.state).to eq('pending')
    expect(JrcApprovals::NotificationOutbox.find_by!(source_event: source).completed_at).to be_nil
    notice = Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: request)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    JrcApprovals::NotificationProjection.new(source.id).call
    expect(Notification.where(account: scope[:account], user: approver.user, primary_actor: request).count).to eq(1)
    expect(JrcApprovals::NotificationOutbox.find_by!(source_event: source).completed_at).to be_present
    expect(notice.reload.id).to eq(notice.id)
  end

  it 'notifies the original requester after a native decision without disclosing the reason or commercial context' do
    vote = approval_vote(scope, approver, request)
    source = JrcApprovals::AuditEvent.find_by!(decision_id: vote.id, event_type: 'decision_recorded')
    JrcApprovals::NotificationProjection.new(source.id).call
    notice = Notification.find_by!(account: scope[:account], user: author.user, primary_actor: request)
    expect(request.reload.state).to eq('approved')
    expect(notice.meta['approval_event']).to eq('decision_recorded')
    expect(notice.push_event_data.to_json).not_to include(vote.reason, 'snapshot', 'values')
  end

  it 'reauthorizes counts and serialization after a permission revocation using current records, even with cached associations' do
    JrcApprovals::NotificationProjection.new(event.id).call
    notice = Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: request)
    expect(JrcApprovals::Notifications.visible?(notice)).to be(true)
    approver.custom_role.update!(permissions: ['jrc_approvals_request_create'])
    expect(notice.push_event_data).to eq({})
    expect(NotificationFinder.new(approver.user, scope[:account]).unread_count).to eq(0)
    expect(NotificationFinder.new(approver.user, scope[:account]).count).to eq(0)
  end

  it 'hides a cached notice when the account or exact unit is deactivated' do
    JrcApprovals::NotificationProjection.new(event.id).call
    notice = Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: request)
    expect(notice.push_event_data).not_to be_empty
    scope[:account].disable_features!('jrc_approvals')
    expect(notice.push_event_data).to eq({})
    scope[:account].enable_features!('jrc_approvals')
    scope[:unit].update!(active: false)
    expect(NotificationFinder.new(approver.user, scope[:account]).count).to eq(0)
  end

  it 'cannot expose another tenant actor or arbitrary metadata in a native notification row' do
    source = event
    other_scope = approval_scope
    other = approval_actor(other_scope)
    fake = Notification.create!(
      account: other_scope[:account], user: other.user, primary_actor: request,
      notification_type: 'approval_event', meta: { 'approval_event' => 'request_created', 'secret' => 'Synthetic private token' }
    )
    expect(fake.push_event_data).to eq({})
    expect(NotificationFinder.new(other.user, other_scope[:account]).count).to eq(0)
    expect(source.account_id).to eq(scope[:account].id)
  end

  it 'checks current access before ActionCable broadcast and only publishes the bounded payload' do
    JrcApprovals::NotificationProjection.new(event.id).call
    notice = Notification.find_by!(account: scope[:account], user: approver.user, primary_actor: request)
    listener = ActionCableListener.instance
    allow(listener).to receive(:broadcast)
    envelope = Struct.new(:data).new({ notification: notice })
    listener.notification_updated(envelope)
    expect(listener).to have_received(:broadcast).once
    approver.custom_role.update!(permissions: ['jrc_approvals_request_create'])
    listener.notification_created(envelope)
    listener.notification_updated(envelope)
    expect(listener).to have_received(:broadcast).once
  end

  it 'records a scheduled own grant immediately and an expiry event once, without rewriting the immutable grant' do
    service = JrcApprovals::OwnDelegations.new(account: scope[:account], user: approver.user)
    future = service.create!(
      delegate_id: author.id,
      issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, actions: ['approved'],
      starts_at: 1.minute.from_now, ends_at: 2.minutes.from_now, idempotency_key: 'notify-scheduled'
    )
    JrcApprovals::NotificationProjection.new(future.id).call
    expect(Notification.where(account: scope[:account], user: author.user, primary_actor: future.record).count).to eq(1)
    captured = future.record.attributes.deep_dup
    travel_to(3.minutes.from_now) do
      2.times { JrcApprovals::DelegationExpiryNotifications.call }
      events = JrcApprovals::AuditEvent.where(account: scope[:account], event_type: 'own_delegation_expired')
      expect(events.count).to eq(1)
      JrcApprovals::NotificationProjection.new(events.first.id).call
      expect(Notification.where(account: scope[:account], user: approver.user, primary_actor: future.record).count).to eq(1)
    end
    expect(future.record.reload.attributes).to eq(captured)
  end

  it 'recovers queued source events through the scheduled job and completes only after projection' do
    source = event
    clear_enqueued_jobs
    JrcApprovals::NotificationRecoveryJob.perform_now
    queued = enqueued_jobs.select { |job| job[:job] == JrcApprovals::NotificationProjectionJob }
    expect(queued.size).to be <= 100
    expect(queued.map { |job| job[:args] }).to include([source.id])
    expect(JrcApprovals::NotificationOutbox.find_by!(source_event: source).completed_at).to be_nil
    JrcApprovals::NotificationProjectionJob.perform_now(source.id)
    expect(JrcApprovals::NotificationOutbox.find_by!(source_event: source).completed_at).to be_present
  end

  it 'notifies both parties of scoped revocation without changing the captured request plan' do
    record = request
    old_plan = record.stage_plan.deep_dup
    delegate = approval_actor(scope)
    manager = JrcApprovals::Delegations.new(account: scope[:account], user: author.user)
    grant = manager.create!(
      policy_version_id: rule.current_version_id, step_code: 'review', principal_id: approver.id,
      delegate_id: delegate.id, actions: ['approved'], reason: 'Synthetic absence', starts_at: 1.minute.ago, ends_at: 1.hour.from_now
    )
    created = JrcApprovals::AuditEvent.find_by!(account: scope[:account], correlation_key: "delegation:#{grant.id}:grant")
    JrcApprovals::NotificationProjection.new(created.id).call
    expect(Notification.where(account: scope[:account], user: delegate.user, primary_actor: created).count).to eq(1)
    manager.revoke!(id: grant.id)
    revoked = JrcApprovals::AuditEvent.find_by!(account: scope[:account], event_type: 'delegation_revoked')
    JrcApprovals::NotificationProjection.new(revoked.id).call
    expect(Notification.where(account: scope[:account],
                              primary_actor: created).pluck(:user_id)).to contain_exactly(approver.user_id, delegate.user_id)
    expect(record.reload.stage_plan).to eq(old_plan)
  end

  it 'protects the persisted outbox source with PostgreSQL and keeps historical events outside automatic backfill' do
    source = event
    row = JrcApprovals::NotificationOutbox.find_by!(source_event: source)
    other = approval_scope
    expect do
      ApplicationRecord.connection.execute("UPDATE jrc_approvals_notification_outboxes SET account_id=#{other[:account].id} WHERE id=#{row.id}")
    end
      .to raise_error(ActiveRecord::StatementInvalid, /source and completion are immutable/)
    expect(row.reload.account_id).to eq(scope[:account].id)
    expect(JrcApprovals::AuditEvent.where(event_type: 'policy_published', account: scope[:account])
      .where.not(id: JrcApprovals::NotificationOutbox.select(:source_event_id))).to exist
  end
end
