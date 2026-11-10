# Read-only completion check against preserved real worker receipts.
# This does not start a worker, enqueue jobs, regenerate notices or alter grants.
class JrcOwnedApprovalReceiptVerification < JrcOwnedApprovalWorkerGate
  def run
    validate_environment!
    @phase = 'retained_real_delivery_receipts'
    load_retained_fixture!
    verify_notice!
    verify_native_cable!
    verify_native_counts!
    verify_retained_jobs!
    verify_original_allocations!
    @passed = true
    @shutdown_clean = true
  ensure
    write_report!
  end

  private

  def load_retained_fixture!
    check!('five actual retained job acknowledgments', acknowledgments == 5)
    @notice_account = Account.find_by!(name: "Synthetic approval worker #{@nonce}")
    @principal = existing_member!('principal', %w[jrc_approvals_decide jrc_approvals_delegate])
    @delegate = existing_member!('delegate', %w[jrc_approvals_decide])
    @blocked_delegate = existing_member!('blocked', [])
    @event = JrcApprovals::AuditEvent.where(account: @notice_account, event_type: JrcApprovals::OwnDelegations::EVENT)
                                     .where("data ->> 'delegate_id' = ?", @delegate.id.to_s).sole
    @notice = Notification.find_by!(account: @notice_account, user: @delegate.user, primary_actor: @event)
    check!('original native notice marked read', @notice.read_at.present?)
  end

  def verify_native_counts!
    unread = NotificationFinder.new(@delegate.user, @notice_account)
    all = NotificationFinder.new(@delegate.user, @notice_account, includes: ['read'])
    check!('default native count excludes read notices', unread.count.zero? && unread.unread_count.zero?)
    check!('explicit read inclusion retains one native notice', all.count == 1 && all.unread_count.zero?)
    check!('revoked recipient has no notification row', Notification.where(account: @notice_account, user: @blocked_delegate.user).none?)
    rows = JrcApprovals::NotificationOutbox.where(account: @notice_account)
    check!('both native outbox rows completed', rows.count == 2 && rows.where(completed_at: nil).none?)
  end

  def verify_retained_jobs!
    attempt = ENV.fetch('JRC_G_APPROVAL_DELIVERY_ATTEMPT')
    raise 'Exact retained attempt required' unless attempt.match?(/\A[0-9a-f]{8}\z/)

    network = JSON.parse(File.read("/tmp/jrc_g_worker_#{@nonce}/attempt_#{attempt}/network.json"))
    check!('retained worker had no HTTP email or push', network.fetch('attempts').zero? && network.fetch('external_delivery_requested') == false)
    count = Sidekiq::Queue.new(@queue).size
    check!('owned business queue remains empty', count.zero?)
    check!('read-only runner attempted no HTTP', WebMock::RequestRegistry.instance.requested_signatures.hash.empty?)
    check!('read-only runner enqueued no jobs', ActiveJob::Base.queue_adapter.enqueued_jobs.empty?)
  end

  def verify_original_allocations!
    account = Account.find_by!(name: 'Synthetic owned worker primary')
    actor = User.find_by!(email: "success-#{@nonce}@example.invalid")
    plan = JrcRelationship::BatchReviewPlan.new(JrcRelationship::Context.new(account.account_users.find_by!(user: actor)))
    reviews = JrcRelationship::BatchReview.where(account: account)
    pins = reviews.flat_map { |review| review.snapshot.fetch('rows') }.uniq { |row| row.fetch('assignment_id') }
    check!('all fourteen original source digests preserved', pins.size == 14 && pins.all? do |pin|
      plan.row_snapshot(JrcRelationship::Assignment.find(pin.fetch('assignment_id'))) == pin
    end)
  end
end
