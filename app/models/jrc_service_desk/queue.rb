# frozen_string_literal: true

# A Service Desk work queue, not a voice queue and not an access grant.
class JrcServiceDesk::Queue < JrcServiceDesk::NamedUnitRecord
  belongs_to :team, class_name: '::Team', optional: true
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error

  validate :team_account_is_consistent
  validate :used_queue_team_is_stable, on: :update

  private

  def team_account_is_consistent
    validate_account_reference(:team)
  end

  def used_queue_team_is_stable
    return unless will_save_change_to_team_id? && tickets.exists?

    errors.add(:team, 'cannot change while tickets reference the queue')
  end
end
