class JrcNico::Helpdesk::CycleEvidence
  FIELDS = %w[negative_return_cycle_key negative_return_at negative_return_attested_by].freeze

  # Callers must authorize the ticket's native history before inspecting the cycle.
  def self.key(ticket)
    reopen = ticket.lifecycle_transitions.where(action: 'reopen').order(:id).last
    "service-desk:ticket:#{ticket.id}:cycle:#{reopen&.id || 'initial'}"
  end

  def self.valid_negative?(ticket:, profile:, cycle_key:, context:, now:)
    evidence = profile&.evidence || {}
    return false unless metadata_valid?(evidence, cycle_key, context)

    at = Time.iso8601(evidence.fetch('negative_return_at'))
    boundary = anchor(ticket, context)
    boundary.present? && at >= boundary && at <= now
  rescue ArgumentError, KeyError
    false
  end

  def self.metadata_valid?(evidence, cycle_key, context)
    return false unless evidence['negative_return'] == true && evidence['negative_return_cycle_key'] == cycle_key
    return false unless context.native.capability?(:history_view)

    context.account.account_users.exists?(id: evidence['negative_return_attested_by'])
  end

  def self.anchor(ticket, context)
    return ticket.lifecycle_transitions.where(action: 'close').maximum(:occurred_at) if ticket.status.phase == 'closed'
    return unless ticket.status.phase == 'waiting' && context.native.capability?(:approvals_view)

    ticket.ticket_approvals.where(status: 'pending').maximum(:created_at)
  end
end
