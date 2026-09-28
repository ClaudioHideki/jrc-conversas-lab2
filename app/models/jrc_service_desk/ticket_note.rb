# frozen_string_literal: true

# Internal only. Channel responses remain native Messages.
class JrcServiceDesk::TicketNote < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  belongs_to :author_membership, class_name: 'JrcServiceDesk::UnitMembership', optional: false
  has_many_attached :files

  validates :idempotency_key, presence: true, length: { maximum: 120 },
                               uniqueness: { scope: %i[account_id unit_id ticket_id author_membership_id] }
  validates :request_fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :body, presence: true, length: { maximum: 50_000 }
  validates :visibility, inclusion: { in: ['internal'] }
  validate :author_scope_is_consistent

  private

  def author_scope_is_consistent
    validate_unit_reference(:author_membership)
    validate_active_reference(:author_membership)
  end
end
