class JrcNico::Helpdesk::BrokerHealth
  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member)
  end

  def call(binding:)
    raise Pundit::NotAuthorizedError unless binding.account_id == @context.account.id

    JrcBroker::Control.new(account: @context.account, user: @context.member.user,
                           account_user: @context.member, binding: binding).status
  end
end
