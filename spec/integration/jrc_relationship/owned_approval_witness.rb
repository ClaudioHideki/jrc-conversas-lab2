# Observes the native ActionCable test adapter without clearing or replacing it.
# Only bounded facts are kept in the owned Redis receipt; never stream tokens/content.
class JrcOwnedApprovalWitness
  def self.capture(job, key)
    members = job.fetch('args').sole.fetch('arguments').first
    raise 'Explicit native cable recipients required' unless members.is_a?(Array) && members.all?(String)

    members.each do |token|
      bounded = observe(token)
      Sidekiq.redis { |redis| redis.call('HSET', "#{key}:cable", job.fetch('jid'), JSON.generate(bounded)) }
    end
  end

  def self.observe(token)
    raw = ActionCable.server.pubsub.broadcasts(token).last
    raise 'Native cable emission required' unless raw

    payload = JSON.parse(raw)
    data = payload.fetch('data')
    notice = data.fetch('notification')
    raise 'Owned approval payload required' unless notice.fetch('notification_type') == 'approval_event' &&
                                                   notice.fetch('account_id') == ENV.fetch('JRC_G_NOTICE_ACCOUNT_ID').to_i

    facts(payload, data, notice).merge(private_reason_omitted: raw.exclude?('PRIVATE_SYNTHETIC_DELEGATION_REASON') && raw.exclude?('@example.invalid'))
  end

  def self.facts(payload, data, notice)
    meta = notice.fetch('meta')
    { event: payload.fetch('event'), unread_count: data.fetch('unread_count'), count: data.fetch('count'),
      approval_event: meta.fetch('approval_event'), target: meta.fetch('approval_target') }
  end
  private_class_method :observe, :facts
end
