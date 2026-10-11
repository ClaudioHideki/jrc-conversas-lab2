# The Account lock is always acquired before the reservation lock.
# No prompts, credentials or provider error bodies belong in this journal.
class JrcNico::ReservationLedger
  LEASE = 3.minutes
  QUEUE_TTL = 15.minutes

  def initialize(record)
    @record = record
  end

  def prepare!(kind:, provider: nil, request_id: nil)
    raise JrcNico::RuntimeClient::Error, 'invalid_scope' if provider && provider.account_id != @record.account_id

    locked do
      @record.update!(lease_expires_at: LEASE.from_now, accounting: {
        'version' => 1, 'request_id' => request_id || stored_request_id, 'kind' => kind, 'provider_id' => provider&.id,
        'basis' => 'reserved', 'reserved_at' => Time.current.iso8601(6)
      })
    end
  end

  def dispatched!
    locked do
      raise JrcNico::RuntimeClient::Error, 'request_cancelled' unless @record.status == 'running' && @record.lease_expires_at&.future?

      journal!('dispatch_started_at' => Time.current.iso8601(6))
    end
  end

  def receipt!(result)
    return unless result['mode'] == 'provider'

    locked do
      usage = result.fetch('usage').stringify_keys
      valid = [nil, true].include?(result['usage_estimated']) && result['model'].is_a?(String) && result['model'].length.between?(1, 150) &&
              usage.keys.sort == %w[input_tokens output_tokens total_tokens] &&
              usage.values.all? { |n| n.is_a?(Integer) && n.between?(0, 270_000) } &&
              usage['input_tokens'] + usage['output_tokens'] == usage['total_tokens']
      raise JrcNico::RuntimeClient::Error, 'provider_usage_invalid' unless valid

      event = events.first
      if event
        raise JrcNico::RuntimeClient::Error, 'provider_usage_invalid' unless event.total_tokens == usage['total_tokens']

        next if @record.reserved_tokens.zero? && @record.accounting['usage_event_id'] == event.id
      else
        event = JrcAi::UsageEvent.create!(account: @record.account, user: @record.user,
                                         provider_id: @record.accounting['provider_id'],
                                         agent_key: run? ? @record.agent_key : 'nico',
                                         feature: run? ? 'assisted_analysis' : "nico_#{@record.accounting.fetch('kind')}",
                                         model: result.fetch('model'), **usage.symbolize_keys, created_at: @record.created_at,
                                         metadata: { correlation_key => @record.id, request_id: stored_request_id, cost_available: false,
                                                     usage_estimated: result['usage_estimated'] == true, accounting_version: 1 })
      end
      journal!('usage_event_id' => event.id, 'basis' => event.metadata['usage_estimated'] == true ? 'estimated' : 'confirmed',
               'receipt_at' => Time.current.iso8601(6))
      @record.update!(reserved_tokens: 0)
    end
  end

  def complete!(result)
    raise JrcNico::RuntimeClient::Error, 'invalid_response' unless %w[provider fixture].include?(result['mode'])
    raise JrcNico::RuntimeClient::Error, 'invalid_response' if ENV['NICO_MODE'] == 'provider' && result['mode'] != 'provider'

    receipt!(result)
    locked do
      if run?
        @record.update!(status: 'completed', result: result, finished_at: Time.current, reserved_tokens: 0) if @record.status == 'running'
      else
        return if @record.status == 'completed'

        raise JrcNico::RuntimeClient::Error, 'request_cancelled' unless @record.status == 'running'

        @record.update!(status: 'completed', reserved_tokens: 0)
      end
    end
  end

  def failed!(error)
    locked do
      return if @record.status == 'completed'

      known = events.exists?
      not_executed = @record.accounting['version'] == 1 &&
                     (@record.accounting['dispatch_started_at'].nil? || (error.is_a?(JrcNico::RuntimeClient::Error) && error.not_executed?))
      code = error.is_a?(JrcNico::RuntimeClient::Error) ? error.code : 'analysis_unavailable'
      basis = if known
                events.first.metadata['usage_estimated'] == true ? 'estimated' : 'confirmed'
              else
                not_executed ? 'not_executed' : 'unknown'
              end
      journal!('basis' => basis, 'error_code' => code, 'failed_at' => Time.current.iso8601(6))
      @record.reserved_tokens = 0 if known || not_executed
      if run?
        @record.assign_attributes(status: 'failed', error_code: 'analysis_unavailable', finished_at: Time.current) if @record.status == 'running'
      else
        @record.status = basis == 'unknown' ? 'unknown' : 'failed'
      end
      @record.save!
    end
  end

  def events
    @record.account.jrc_ai_usage_events.where("metadata ->> ? = ?", correlation_key, @record.id.to_s)
           .where(agent_key: run? ? @record.agent_key : 'nico')
           .where(run? ? "feature = 'assisted_analysis'" : "feature LIKE 'nico_%'")
  end

  def self.receipt_condition(model)
    table = model.table_name
    run = model == JrcNico::Run
    key = run ? 'run_id' : 'inference_id'
    agent = run ? "u.agent_key = #{table}.agent_key AND u.feature = 'assisted_analysis'" : "u.agent_key = 'nico' AND u.feature LIKE 'nico_%'"
    "EXISTS (SELECT 1 FROM jrc_ai_usage_events u WHERE u.account_id = #{table}.account_id AND u.metadata ->> '#{key}' = #{table}.id::text AND #{agent})"
  end

  private

  def locked(&block)
    @record.account.with_lock { @record.with_lock(&block) }
  end

  def run?
    @record.is_a?(JrcNico::Run)
  end

  def correlation_key
    run? ? 'run_id' : 'inference_id'
  end

  def stored_request_id
    @record.accounting['request_id'] || (run? ? @record.request_id : SecureRandom.uuid)
  end

  def journal!(values)
    @record.update!(accounting: @record.accounting.merge(values))
  end
end
