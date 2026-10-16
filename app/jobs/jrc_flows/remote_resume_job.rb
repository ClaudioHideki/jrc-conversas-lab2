class JrcFlows::RemoteResumeJob < ApplicationJob
  queue_as :default

  def perform(session_id)
    return unless JrcFlows::Access.external_beta?

    session = JrcFlowRemoteSession.find_by(id: session_id)
    return unless session && session.wake_at && session.wake_at <= Time.current && %w[waiting delayed].include?(session.status)

    lock_id = Digest::SHA256.hexdigest("jrc-remote:#{session.connection_id}:#{session.conversation_id}")[0, 15].to_i(16)
    ActiveRecord::Base.connection_pool.with_connection do |db|
      return unless db.select_value("SELECT pg_try_advisory_lock(#{lock_id})")

      begin
        session.reload
        return unless session.wake_at && session.wake_at <= Time.current && %w[waiting delayed].include?(session.status)

        JrcFlows::RemoteRunner.new(session.connection).resume(session)
      ensure
        db.select_value("SELECT pg_advisory_unlock(#{lock_id})")
      end
    end
  end
end

JrcFlows::RemoteResumeJob.prepend(JrcFlows::OwnershipEntrypoints::RemoteResume)
