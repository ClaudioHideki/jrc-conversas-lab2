class JrcNico::PlanCommandJob < ApplicationJob
  queue_as :default

  def perform(command_id)
    command = JrcNico::Command.find_by(id: command_id)
    return unless command

    claimed = command.with_lock do
      next false unless command.status == 'planning' && command.execution_context['async_planning'] == true
      next false if command.execution_context['planning_started_at']

      command.update!(execution_context: command.execution_context.merge('planning_started_at' => Time.current.iso8601(6)))
      true
    end
    return unless claimed

    session = command.session
    operator = JrcNico::OperatorSession.new(account: session.account, user: session.user)
    operator.plan_queued(command)
  rescue StandardError => error
    # A redelivered job must never repeat a possibly billed dispatch or a write.
    if claimed && command&.reload&.status == 'planning'
      command.update!(status: 'failed', reply: 'Não foi possível preparar o pedido. Confira suas permissões e tente um novo pedido.')
    end
    Rails.logger.warn("NICO planning failed command_id=#{command_id} type=#{error.class.name}")
  end
end
