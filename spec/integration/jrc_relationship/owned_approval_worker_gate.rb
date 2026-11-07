# Explicit real queue gate; never discovered as an RSpec test or provider demo.
raise 'Approval worker mode required' unless ENV['JRC_G_MODE'] == 'approvals'

require_relative 'owned_worker_gate'

class JrcOwnedApprovalWorkerGate < JrcOwnedWorkerGate
  private

  def resume_fixtures!
    verify_initial_receipts!
    @original_accounts = Account.order(:id).map(&:attributes)
    @original_assignments = JrcRelationship::Assignment.order(:id).map(&:attributes)
    @original_reviews = JrcRelationship::BatchReview.order(:id).map(&:attributes)
    @original_items = JrcRelationship::BatchItem.order(:id).map(&:attributes)
    ENV['JRC_G_APPROVAL_RESUME'].present? ? resume_approval_fixture! : prepare_approval_fixture!
    configure_approval_jobs!
  end

  def verify_initial_receipts!
    check!('prior business receipts preserved', Sidekiq.redis { |redis| redis.call('SCARD', "jrc_g_worker:#{@nonce}:ack") } == 5)
    pending_count = Sidekiq::Queue.new(@queue).size
    expected = ENV['JRC_G_APPROVAL_RESUME'].present? ? 2 : 0
    check!('exact prior approval receipts and empty business queue', acknowledgments == expected && pending_count.zero?)
  end

  def prepare_approval_fixture!
    @notice_account = Account.create!(name: "Synthetic approval worker #{@nonce}")
    @notice_account.enable_features!('jrc_crm', 'jrc_approvals')
    @principal = approval_member!('principal', %w[jrc_approvals_decide jrc_approvals_delegate])
    @delegate = approval_member!('delegate', %w[jrc_approvals_decide])
    @blocked_delegate = approval_member!('blocked', %w[jrc_approvals_decide])
    @service = JrcApprovals::OwnDelegations.new(account: @notice_account, user: @principal.user)
    @grant = grant!(@delegate)
    @event = @grant.record
    @event_attributes = @event.attributes.deep_dup
    ENV['JRC_G_NOTICE_ACCOUNT_ID'] = @notice_account.id.to_s
    check!('domain committed its native outbox', outbox(@event).completed_at.nil?)
  end

  def configure_approval_jobs!
    [JrcApprovals::NotificationProjectionJob, JrcApprovals::NotificationRecoveryJob, EventDispatcherJob, ActionCableBroadcastJob].each do |job|
      job.queue_adapter = :sidekiq
      job.queue_as @queue
    end
  end

  def resume_approval_fixture!
    @notice_account = Account.find_by!(name: "Synthetic approval worker #{@nonce}")
    @principal = existing_member!('principal', %w[jrc_approvals_decide jrc_approvals_delegate])
    @delegate = existing_member!('delegate', %w[jrc_approvals_decide])
    @blocked_delegate = existing_member!('blocked', %w[jrc_approvals_decide])
    @service = JrcApprovals::OwnDelegations.new(account: @notice_account, user: @principal.user)
    @event = JrcApprovals::AuditEvent.where(account: @notice_account, event_type: JrcApprovals::OwnDelegations::EVENT).sole
    @grant = JrcApprovals::OwnDelegation.new(@event)
    @event_attributes = @event.attributes.deep_dup
    ENV['JRC_G_NOTICE_ACCOUNT_ID'] = @notice_account.id.to_s
    verify_original_notice!
  end

  def verify_original_notice!
    check!('original positive outbox complete', outbox(@event).completed_at.present?)
    check!('exact original delegation parties', @grant.principal_id == @principal.id && @grant.delegate_id == @delegate.id && !@grant.revoked?)
    check!('only original notice exists', Notification.where(account: @notice_account).count == 1)
  end

  def existing_member!(label, permissions)
    user = User.find_by!(email: "#{label}-approval-#{@nonce}@example.invalid")
    member = @notice_account.account_users.find_by!(user: user)
    check!('preserved explicit approval role', member.agent? && member.custom_role.permissions.sort == permissions.sort)
    check!('preserved native group coverage', @notice_account.jrc_crm_user_business_units.exists?(user: user, scope: 'GROUP',
                                                                                                  active: true, structure_managed: true))
    member
  end

  def approval_member!(label, permissions)
    role = @notice_account.custom_roles.create!(name: "Synthetic #{label}", permissions: permissions)
    user = User.create!(name: "Synthetic approval #{label}", email: "#{label}-approval-#{@nonce}@example.invalid",
                        password: "Aa1!#{SecureRandom.hex(20)}", confirmed_at: Time.current)
    member = AccountUser.create!(account: @notice_account, user: user, role: :agent, custom_role: role)
    @notice_account.jrc_crm_user_business_units.create!(user: user, scope: 'GROUP', active: true, structure_managed: true)
    member
  end

  def grant!(delegate)
    @service.create!(delegate_id: delegate.id, issuer_company_id: nil, business_unit_id: nil, actions: ['approved'],
                     reason: 'PRIVATE_SYNTHETIC_DELEGATION_REASON', starts_at: 1.minute.ago, ends_at: 1.hour.from_now,
                     idempotency_key: SecureRandom.uuid)
  end

  def outbox(event)
    JrcApprovals::NotificationOutbox.uncached do
      JrcApprovals::NotificationOutbox.find_by!(account: @notice_account, source_event: event)
    end
  end

  def enqueue_job(job, *)
    delivered = job.set(queue: @queue).perform_later(*)
    check!('actual Redis provider delivery ID', delivered.provider_job_id.is_a?(String) && !delivered.provider_job_id.empty?)
  end

  def exercise!
    verify_recovered_notice!
    replay_notice!
    reject_revoked_recipient!
    verify_native_cable!
    verify_preserved_graph!
    check!('main made no HTTP requests', WebMock::RequestRegistry.instance.requested_signatures.hash.empty?)
    pending_count = Sidekiq::Queue.new(@queue).size
    check!('approval queue drained', pending_count.zero?)
  end

  def verify_recovered_notice!
    @phase = 'native_outbox_recovery'
    enqueue_job(JrcApprovals::NotificationRecoveryJob) if ENV['JRC_G_APPROVAL_RESUME'].blank?
    wait_for('native recovery and projection') { outbox(@event).completed_at.present? && acknowledgments == 2 }
    @notice = Notification.find_by!(account: @notice_account, user: @delegate.user, primary_actor: @event, notification_type: 'approval_event')
    verify_notice!
    wait_for('native created cable emitted') { Sidekiq.redis { |redis| redis.call('HLEN', "#{@receipt_key}:cable") } == 1 }
  end

  def verify_notice!
    payload = @notice.push_event_data
    check!('native bounded notification target', payload.fetch('meta') == { 'approval_event' => 'own_delegation_granted',
                                                                            'approval_target' => 'own-delegations' })
    check!('private approval content omitted', payload.to_json.exclude?('PRIVATE_SYNTHETIC_DELEGATION_REASON') &&
                                             payload.to_json.exclude?(@delegate.user.email))
    foreign = User.find_by!(email: "foreign-#{@nonce}@example.invalid")
    check!('foreign account cannot read notification actor', !JrcApprovals::Notifications.actor_visible?(
      account: @notice_account, user: foreign, actor: @event
    ))
  end

  def replay_notice!
    @phase = 'native_notice_duplicate'
    @notice.update!(read_at: Time.current)
    original = @notice.reload.attributes
    enqueue_job(JrcApprovals::NotificationProjectionJob, @event.id)
    wait_for('duplicate projection') { acknowledgments == 3 }
    check!('duplicate keeps read mark and native row', @notice.reload.attributes == original &&
           Notification.where(account: @notice_account, user: @delegate.user, primary_actor: @event).count == 1)
  end

  def reject_revoked_recipient!
    @phase = 'native_notice_revoked_recipient'
    grant = grant!(@blocked_delegate)
    @blocked_delegate.custom_role.update!(permissions: [])
    enqueue_job(JrcApprovals::NotificationRecoveryJob)
    wait_for('revoked recipient projection') { outbox(grant.record).completed_at.present? && acknowledgments == 5 }
    check!('revoked recipient receives no private notice', Notification.where(account: @notice_account, user: @blocked_delegate.user).none?)
    check!('original grant remains immutable', @event.reload.attributes == @event_attributes)
  end

  def verify_native_cable!
    wait_for('native cable creation and read update') do
      Sidekiq.redis { |redis| redis.call('HLEN', "#{@receipt_key}:cable") } == 2
    end
    rows = Sidekiq.redis { |redis| redis.call('HVALS', "#{@receipt_key}:cable") }.map { |raw| JSON.parse(raw) }
    check!('native cable has real created and read counts', rows.map { |row| row.values_at('event', 'unread_count', 'count') }.sort ==
           [['notification.created', 1, 1], ['notification.updated', 0, 0]])
    check!('native cable omits private approval context', rows.all? do |row|
      row['private_reason_omitted'] && row['target'] == 'own-delegations' && row['approval_event'] == 'own_delegation_granted'
    end)
  end

  def verify_preserved_graph!
    @phase = 'preserved_graph_and_network'
    ids = @original_accounts.pluck('id')
    check!('original synthetic accounts unchanged', Account.where(id: ids).order(:id).map(&:attributes) == @original_accounts)
    check!('original native assignments unchanged', JrcRelationship::Assignment.order(:id).map(&:attributes) == @original_assignments)
    check!('original reviews and receipts unchanged', JrcRelationship::BatchReview.order(:id).map(&:attributes) == @original_reviews &&
           JrcRelationship::BatchItem.order(:id).map(&:attributes) == @original_items)
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job].name }
    check!('no email or push delivery requested', !jobs.intersect?(%w[Notification::EmailNotificationJob Notification::PushNotificationJob]))
  end
end

if ENV['JRC_G_APPROVAL_FINALIZE'] == 'true'
  require_relative 'owned_approval_receipt_verification'
  JrcOwnedApprovalReceiptVerification.new.run
else
  JrcOwnedApprovalWorkerGate.new.run
end
