class JrcFlows::RemoteRecoveryJob < ApplicationJob
  queue_as :default

  def perform
    return unless JrcFlows::Access.external_beta?

    JrcFlowRemoteEvent.where(status: 'queued').where('created_at < ?', 30.seconds.ago).limit(100).pluck(:id).each do |id|
      JrcFlows::RemoteEventJob.perform_later(id)
    end
    JrcFlowRemoteEvent.where(status: 'running').where('claimed_at < ?', 10.minutes.ago).update_all(
      status: 'failed', error: 'Execução interrompida; verifique efeitos externos antes de repetir.'
    )
    JrcFlowRemoteSession.where(status: 'running').where('claimed_at < ?', 3.minutes.ago).update_all(
      status: 'failed', error: 'Execução interrompida; resultado externo incerto.', wake_at: nil
    )
    JrcFlowRemoteSession.where(status: %w[waiting delayed]).where('wake_at <= ?', Time.current).limit(100).pluck(:id).each do |id|
      JrcFlows::RemoteResumeJob.perform_later(id)
    end
    JrcFlowRemoteEvent.where(status: %w[completed failed]).where('created_at < ?', 7.days.ago).limit(1000).delete_all
  end
end

JrcFlows::RemoteRecoveryJob.prepend(JrcFlows::OwnershipEntrypoints::RemoteRecovery)
