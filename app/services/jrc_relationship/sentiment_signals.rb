# Reads existing analysis only. Private notes, future messages and conversations
# outside the native source scope never contribute or renew an observation.
class JrcRelationship::SentimentSignals
  def initialize(context:, customer:, window_days:, now: Time.current)
    @window_days = window_days
    @now = now
    @source = Message.where(account_id: context.account.id, conversation_id: customer.conversations.select(:id),
                            private: false, message_type: [0, 1]).where("sentiment IS NOT NULL AND sentiment <> '{}'::jsonb")
  end

  def call
    current = metric(@source.where(created_at: (@now - @window_days.days)..@now))
    observed = current[:source_ids].any? ? current : metric(@source.where('created_at < ?', @now - @window_days.days))
    state = if current[:normalized].nil?
              observed[:source_ids].any? ? 'stale' : 'missing'
            else
              'current'
            end
    timestamp = @source.where(id: observed[:source_ids]).maximum(:created_at)
    measurement = { state: state, window_days: @window_days, source: 'existing_public_message_sentiment',
                    observed_at: timestamp&.iso8601(6), sample_limit: 100 }
    current.merge(measurement: measurement, source_ids: (current[:source_ids] + observed[:source_ids]).uniq)
  end

  private

  def metric(source)
    JrcRelationship::SentimentMetric.call(source.reorder(created_at: :desc, id: :desc).limit(100).pluck(:id, :sentiment))
  end
end
