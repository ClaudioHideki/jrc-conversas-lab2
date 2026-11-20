# frozen_string_literal: true

# One module-local status and its manager receipt inside the account authority transaction.
class JrcContactCenter::TeamActivityChange
  def initialize(account:, actor:, team:, active:, revision:)
    @account = account
    @actor = actor
    @team = team
    @state = JrcContactCenter::TeamState.find_or_initialize_by(account: account, team: team)
    @active = active
    @revision = revision
    raise JrcContactCenter::OperationError, 'invalid_access_authorization' unless [true, false].include?(active)
  end

  def preview
    changed? ? { @team.id => @active } : {}
  end

  def check!(confirmation:)
    return unless changed? && !@active

    impact = JrcContactCenter::TeamActivityPreview.new(account: @account, actor: @actor, team: @team, revision: @revision)
    @review = JrcContactCenter::TeamActivityWithdrawalReview.new(account: @account, actor: @actor, preview: impact, confirmation: confirmation)
    @review.check!
  end

  def save!
    return unless changed?

    @state.update!(active: @active)
    @review&.audit!
  end

  private

  def changed?
    @state.active != @active
  end
end
