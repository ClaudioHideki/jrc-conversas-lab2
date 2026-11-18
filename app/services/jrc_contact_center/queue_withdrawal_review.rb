# frozen_string_literal: true

require 'digest'

# A signed state precondition for explicit manager review, never an access grant or a PABX command.
class JrcContactCenter::QueueWithdrawalReview
  PURPOSE = 'jrc_cc_last_eligible_withdrawal_v1'
  AUDIT_FIELDS = %w[kind account_user_id queue_id membership_id previous_count remaining_count reviewed_at receipt_sha256].freeze

  class Required < JrcContactCenter::OperationError
    attr_reader :review

    def initialize(review)
      @review = review
      super('last_eligible_confirmation_required', status: :conflict)
    end
  end

  def initialize(account:, member:, confirmation:)
    @account = account
    @member = member
    @confirmation = confirmation
  end

  def check!(record, attributes)
    return unless record.is_a?(JrcContactCenter::QueueMembership) && removes_last_eligible?(record, attributes)

    authorize_manager!(record)
    payload = review_identity(record, attributes)
    received = confirmed_receipt
    raise Required, review_details(record, payload) unless received&.except('issued_at') == payload

    record.cc_withdrawal_review = payload.slice('account_user_id', 'queue_id', 'membership_id').merge(
      'kind' => PURPOSE, 'previous_count' => 1, 'remaining_count' => 0, 'reviewed_at' => Time.current.iso8601(6),
      'receipt_sha256' => Digest::SHA256.hexdigest(@confirmation[:review_token])
    )
  end

  private

  def authorize_manager!(record)
    raise Pundit::NotAuthorizedError unless @member&.account_id == @account.id && record.account_id == @account.id

    @member.reload
    context = { account: @account, account_user: @member, user: @member.user }
    policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    allowed = @member.user.reload.active_for_authentication? && policy.configure?
    raise Pundit::NotAuthorizedError unless allowed

    scope = JrcContactCenter::OrganizationalScope.new(account: @account, account_user: @member)
    raise Pundit::NotAuthorizedError unless scope.units.exists?(record.queue.unit_id)
  end

  def removes_last_eligible?(record, attributes)
    return false unless configured_eligible?(record)

    proposed = record.class.new(record.attributes)
    proposed.assign_attributes(attributes)
    return false if proposed.queue_id == record.queue_id && configured_eligible?(proposed)

    record.queue.memberships.where(account: @account).where.not(id: record.id).none? { |row| configured_eligible?(row) }
  end

  def configured_eligible?(membership)
    return false unless membership.active? && membership.role == 'agent' && active_window?(membership)

    member = @account.account_users.find(membership.account_user_id)
    return false unless authorized_operator?(member)

    queue = JrcContactCenter::Queue.find_by!(account: @account, id: membership.queue_id)
    scope = JrcContactCenter::OrganizationalScope.new(account: @account, account_user: member)
    operational_queue?(queue) && scope.units.exists?(queue.unit_id)
  end

  def authorized_operator?(member)
    context = { account: @account, account_user: member, user: member.user }
    member.user.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?
  end

  def operational_queue?(queue)
    now = Time.current
    queue.status == 'active' && queue.unit.status == 'active' &&
      (!queue.active_from || queue.active_from <= now) && (!queue.active_until || queue.active_until > now)
  end

  def active_window?(membership)
    now = Time.current
    (!membership.starts_at || membership.starts_at <= now) && (!membership.ends_at || membership.ends_at > now)
  end

  def review_identity(record, attributes)
    proposed = record.class.new(record.attributes)
    proposed.assign_attributes(attributes)
    { 'account_id' => @account.id.to_s, 'account_user_id' => @member.id.to_s, 'user_id' => @member.user_id.to_s,
      'queue_id' => record.queue_id.to_s,
      'membership_id' => record.id.to_s, 'previous_revision' => JrcContactCenter::ConfigurationRevision.token(record),
      'proposed_revision' => JrcContactCenter::ConfigurationRevision.token(proposed) }
  end

  def confirmed_receipt
    valid = @confirmation.respond_to?(:keys) && @confirmation[:confirmed] == true && @confirmation[:review_token].is_a?(String)
    return unless valid && @confirmation[:review_token].bytesize <= 4096

    verifier.verified(@confirmation[:review_token], purpose: PURPOSE)
  end

  def review_details(record, payload)
    reviewed = payload.merge('issued_at' => Time.current.iso8601(6))
    { account_id: @account.id.to_s, membership_id: record.id.to_s, queue_id: record.queue_id.to_s, queue_name: record.queue.name,
      previous_count: 1, remaining_count: 0, review_token: verifier.generate(reviewed, expires_in: 10.minutes, purpose: PURPOSE) }
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
