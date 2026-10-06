class JrcCrm::ProposalPublicState
  MESSAGES = {
    'draft' => 'Esta proposta ainda não foi enviada ao cliente.',
    'pending_approval' => 'Esta proposta ainda não foi enviada ao cliente.',
    'approved' => 'Aprovada internamente — aguardando envio ao cliente.',
    'expired' => 'Esta proposta expirou. Solicite uma nova versão ao responsável.',
    'canceled' => 'Esta proposta está indisponível.'
  }.freeze

  def self.call(proposal, now: Time.current)
    state = proposal.status
    state = 'approved' if state == 'draft' && proposal.approval_status == 'approved'
    expired = (proposal.public_token_expires_at && proposal.public_token_expires_at <= now) ||
      (proposal.valid_until && proposal.valid_until < now.to_date)
    state = 'expired' if expired
    state = 'canceled' if proposal.public_token_revoked_at || proposal.status == 'canceled'
    available = !expired && state != 'canceled' && proposal.sent_at && %w[sent viewed accepted rejected].include?(state)
    { state: state, available: !!available, message: MESSAGES[state] || (!available && MESSAGES['draft']) }
  end

  def self.transition_allowed?(from:, to:, sent_at:)
    return true unless %w[viewed accepted rejected].include?(to)

    !!sent_at && %w[sent viewed].include?(from)
  end
end
