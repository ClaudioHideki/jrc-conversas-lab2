# frozen_string_literal: true

require 'digest'

# Explicit local manager review for an indirect withdrawal, not a new permission or provider command.
class JrcContactCenter::TeamRosterWithdrawalReview
  PURPOSE = 'jrc_cc_team_roster_withdrawal_v1'
  AUDIT_FIELDS = (JrcContactCenter::QueueWithdrawalReview::AUDIT_FIELDS + %w[team_id operation roster_sha256]).freeze

  class Required < JrcContactCenter::OperationError
    attr_reader :review

    def initialize(review)
      @review = review
      super('team_roster_confirmation_required', status: :conflict)
    end
  end

  def initialize(account:, actor:, preview:, confirmation:)
    @account = account
    @actor = actor
    @preview = preview
    @confirmation = confirmation
  end

  def check!
    @impacts = @preview.call
    return if @impacts.empty?

    payload = identity
    raise Required, details(payload) unless confirmed_receipt&.except('issued_at') == payload

    @review = payload.slice('account_user_id', 'team_id', 'operation', 'roster_sha256').merge(
      'kind' => PURPOSE, 'reviewed_at' => Time.current.iso8601(6),
      'receipt_sha256' => Digest::SHA256.hexdigest(@confirmation[:review_token])
    )
  end

  def audit!
    return unless @review

    @impacts.each do |impact|
      review = @review.merge(
        'queue_id' => impact.fetch(:queue).id.to_s,
        'previous_count' => impact.fetch(:before_ids).length, 'remaining_count' => impact.fetch(:after_ids).length
      )
      JrcContactCenter::ConfigurationAudit.write_team_withdrawal!(impact.fetch(:queue), review: review)
    end
    @review = nil
  end

  private

  def identity
    { 'account_id' => @account.id.to_s, 'account_user_id' => @actor.id.to_s, 'user_id' => @actor.user_id.to_s,
      'team_id' => @preview.team.id.to_s, 'operation' => @preview.operation, 'roster_sha256' => roster_sha256 }
  end

  def roster_sha256
    queues = @impacts.map do |impact|
      [impact.fetch(:queue).id.to_s, impact.fetch(:before_ids), impact.fetch(:after_ids),
       impact.fetch(:queue_revision), impact.fetch(:unit_revision)]
    end
    Digest::SHA256.hexdigest([@preview.before_ids, @preview.after_ids, queues].to_json)
  end

  def confirmed_receipt
    valid = @confirmation.respond_to?(:keys) && @confirmation[:confirmed] == true && @confirmation[:review_token].is_a?(String)
    return unless valid && @confirmation[:review_token].bytesize <= 4096

    verifier.verified(@confirmation[:review_token], purpose: PURPOSE)
  end

  def details(payload)
    queues = @impacts.map do |impact|
      queue = impact.fetch(:queue)
      { queue_id: queue.id.to_s, queue_name: queue.name, unit_id: queue.unit_id.to_s,
        previous_count: impact.fetch(:before_ids).length, remaining_count: impact.fetch(:after_ids).length }
    end
    { account_id: @account.id.to_s, team_id: @preview.team.id.to_s, team_name: @preview.team.name,
      operation: @preview.operation, queues: queues,
      review_token: verifier.generate(payload.merge('issued_at' => Time.current.iso8601(6)), expires_in: 10.minutes, purpose: PURPOSE) }
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
