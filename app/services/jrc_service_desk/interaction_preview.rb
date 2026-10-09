class JrcServiceDesk::InteractionPreview
  PURPOSE = 'service_desk_interaction'.freeze
  TTL = 5.minutes

  def initialize(ticket:, context:)
    @ticket = ticket
    @context = context
    @plan = JrcServiceDesk::PublicationPlan.new(ticket: ticket, context: context)
  end

  def call(attributes:, file_fingerprints: [])
    plan = @plan.call(attributes, file_fingerprints)
    blocked = plan[:deliveries].find { |delivery| delivery[:reason] }
    receipt = verifier.generate(binding(plan), expires_in: TTL, purpose: PURPOSE)
    plan.merge(can_publish: true, notification_available: blocked.nil?, receipt: receipt, expires_at: (Time.current + TTL).iso8601(6))
  end

  def verify!(receipt, attributes:, file_fingerprints: [])
    approved = verifier.verified(receipt, purpose: PURPOSE) if receipt.is_a?(String)
    current = binding(@plan.call(attributes, file_fingerprints))
    raise JrcServiceDesk::PublicationPreviewError unless approved == current

    current.fetch('digest')
  end

  private

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end

  def binding(plan)
    { 'digest' => JrcServiceDesk::CanonicalJson.digest(plan), 'account_user_id' => @context.account_user.id,
      'account_id' => @ticket.account_id, 'unit_id' => @ticket.unit_id, 'ticket_id' => @ticket.id }
  end
end
