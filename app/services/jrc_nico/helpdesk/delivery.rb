# Every channel has its own durable receipt. Unknown delivery is never retried as a new send.
class JrcNico::Helpdesk::Delivery
  TERMINAL = %w[dispatching sent delivered unknown failed].freeze
  def initialize(source:, recipient:, channel:)
    @source = source
    @recipient = recipient
    @channel = channel
  end

  def call
    raise Pundit::NotAuthorizedError unless @recipient.account_id == @source.account_id

    receipt = find_receipt!
    authorize_source!(JrcNico::Helpdesk::Context.new(@recipient))
    deliver_authorized!(receipt)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound => error
    block_unauthorized!(receipt, error)
  end

  private

  def deliver_authorized!(receipt)
    return JrcNico::Helpdesk::EmailDelivery.new(receipt).call if @channel == 'email'
    return receipt if TERMINAL.include?(receipt.reload.state)

    receipt.with_lock do
      authorize_source!(JrcNico::Helpdesk::Context.new(@recipient))
      next receipt if TERMINAL.include?(receipt.state)

      dispatch!(receipt)
    end
    receipt
  end

  def block_unauthorized!(receipt, error)
    raise error unless receipt && TERMINAL.exclude?(receipt.reload.state)

    receipt.update!(state: 'blocked', reason: 'recipient_permission_revoked', attempted_at: Time.current)
    receipt
  end

  def find_receipt!
    type = @source.is_a?(JrcNico::Helpdesk::Event) ? 'event' : 'daily_report'
    @source.account.with_lock do
      JrcNico::Helpdesk::DeliveryReceipt.find_or_create_by!(account: @source.account, recipient: @recipient,
                                                            source_type: type, source_id: @source.id, channel: @channel)
    end
  end

  def dispatch!(receipt)
    authorize_source!(JrcNico::Helpdesk::Context.new(@recipient))
    unless @source.policy_version.reload.enabled?
      receipt.update!(state: 'blocked', reason: 'activation_disabled', attempted_at: Time.current)
      return
    end
    return deliver_notice!(receipt) if @channel == 'nico'

    receipt.update!(state: 'blocked', reason: 'verified_recipient_and_delivery_adapter_required', attempted_at: Time.current)
  end

  def deliver_notice!(receipt)
    notice = JrcNico::Notice.publish!(account: @source.account, user: @recipient.user,
                                      event_key: "helpdesk:receipt:#{receipt.id}", kind: 'attention', body: body,
                                      metadata: { 'resources' => resources, 'route_name' => 'jrc_nico_helpdesk' })
    receipt.update!(state: 'delivered', remote_id: notice.id.to_s, delivered_at: Time.current, attempted_at: Time.current, reason: nil)
  end

  def resources
    ids = @source.is_a?(JrcNico::Helpdesk::Event) ? [@source.ticket_id] : @source.payload.fetch('ticket_ids')
    ids.map { |id| ['JrcServiceDesk::Ticket', id] }
  end

  def authorize_source!(context)
    JrcNico::Helpdesk::DeliveryAuthorization.new(@source, context.member).call
  end

  def body
    if @source.is_a?(JrcNico::Helpdesk::Event)
      "HelpDesk #{@source.rule_key}: chamado ##{@source.ticket_id}. Revise o evento e as evidências autorizadas."
    else
      "Relatório HelpDesk #{@source.report_date.iso8601}. Consulte os detalhes e pendências de entrega."
    end
  end
end
