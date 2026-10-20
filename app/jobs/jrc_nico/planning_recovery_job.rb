class JrcNico::PlanningRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JrcNico::Command.where(status: 'planning').where('updated_at < ?', 2.minutes.ago).find_each do |command|
      queued = command.with_lock do
        next false unless command.status == 'planning'

        started = command.execution_context['planning_started_at']
        if command.updated_at < 20.minutes.ago && (started || command.execution_context['async_planning'] != true)
          command.update!(status: 'unknown', reply: 'O processamento foi interrompido. Confira os resultados antes de fazer outro pedido.')
          next false
        end
        command.execution_context['async_planning'] == true && started.nil?
      end
      JrcNico::PlanCommandJob.perform_later(command.id) if queued
    end
  end
end
