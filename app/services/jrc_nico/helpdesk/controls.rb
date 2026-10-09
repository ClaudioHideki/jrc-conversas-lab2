class JrcNico::Helpdesk::Controls
  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member).administrator!
  end

  def disable(id:, reason:, request_key:)
    policy = @context.policy(id)
    key = JrcServiceDesk::Input.request_key(request_key)
    raise ArgumentError, 'A bounded explicit reason is required' unless reason.is_a?(String) && reason.strip.size.between?(1, 1000)

    @context.account.with_lock do
      @context.administrator!
      validate_units!(policy)
      previous = JrcNico::Helpdesk::ControlEvent.find_by(account: @context.account, policy_version: policy, actor: @context.member, request_key: key)
      if previous
        raise ArgumentError, 'Control request key changed' unless previous.reason == reason

        next previous
      end
      record_halt!(policy, key, reason)
    end
  end

  private

  def validate_units!(policy)
    configured = policy.definition.fetch('unit_ids')
    units = @context.native.unit_scope.where(id: configured).pluck(:id)
    raise Pundit::NotAuthorizedError unless units.sort == configured.sort
  end

  def record_halt!(policy, key, reason)
    control = JrcNico::Helpdesk::PolicyControl.find_or_initialize_by(account: @context.account, policy_version: policy)
    control.update!(halted: true, halted_at: control.halted_at || Time.current)
    JrcNico::Helpdesk::ControlEvent.create!(account: @context.account, policy_version: policy, actor: @context.member,
                                            action: 'disable', request_key: key, reason: reason, occurred_at: Time.current)
  end
end
