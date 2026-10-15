class JrcFlows::RemoteEventJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    return unless JrcFlows::Access.external_beta?

    event = JrcFlowRemoteEvent.find_by(id: event_id, status: 'queued')
    return unless event

    payload = event.payload
    conversation = payload['conversation'] || payload
    lock_id = Digest::SHA256.hexdigest("jrc-remote:#{event.connection_id}:#{conversation['id']}")[0, 15].to_i(16)
    ActiveRecord::Base.connection_pool.with_connection do |db|
      locked = db.select_value("SELECT pg_try_advisory_lock(#{lock_id})")
      unless locked
        self.class.set(wait: 2.seconds).perform_later(event_id)
        return
      end
      begin
        event.reload
        return unless event.status == 'queued'

        event.update!(status: 'running', claimed_at: Time.current)
        JrcFlows::RemoteRunner.new(event.connection).receive(payload)
        event.update!(status: 'completed')
      ensure
        db.select_value("SELECT pg_advisory_unlock(#{lock_id})")
      end
    end
  rescue StandardError => e
    # External mutations are not retried after an uncertain result.
    event&.update!(status: 'failed',
                   error: e.is_a?(JrcFlows::ChatwootClient::Error) ? e.message.first(240) : 'Falha no processamento. Confira a execução.')
    Rails.logger.warn("JRC remote event=#{event_id} failed #{e.class.name}")
  end
end

JrcFlows::RemoteEventJob.prepend(JrcFlows::OwnershipEntrypoints::RemoteEvent)
