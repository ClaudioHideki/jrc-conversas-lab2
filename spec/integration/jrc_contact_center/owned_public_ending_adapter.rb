# frozen_string_literal: true

# Native test-adapter delegation for the explicit nonce queue only.
class SyntheticPublicEndingQueue::Adapter
  def initialize(previous, configuration)
    @previous = previous
    @configuration = configuration
    @native = ActiveJob::QueueAdapters::SidekiqAdapter.new
  end

  def enqueue(job)
    return @previous.enqueue(job) unless owned?(job)

    job.queue_name = @configuration.fetch('queue')
    @native.enqueue(job)
    record_producer(job)
  end

  def enqueue_at(job, timestamp)
    # No scheduling or retry policy is introduced by the browser witness.
    return @previous.enqueue_at(job, timestamp) unless owned?(job)

    raise 'Unexpected scheduled action in explicit public ending browser flow'
  end

  private

  def owned?(job)
    SyntheticPublicEndingQueue::JOB_CLASSES.include?(job.class.name) && SyntheticPublicEndingQueue.expected_arguments?(job.arguments, @configuration)
  end

  def record_producer(job)
    raise 'Native Sidekiq job ID required' unless job.provider_job_id.to_s.match?(/\A[0-9a-f]{24}\z/)

    receipt = { jid: job.provider_job_id, job_class: job.class.name, account_id: job.arguments.first,
                record_id: job.arguments.last, producer_pid: Process.pid, source_sha: @configuration.fetch('source_sha'),
                queue: job.queue_name, witness_sha256: Digest::SHA256.file(__FILE__).hexdigest }
    Redis.new(url: ENV.fetch('REDIS_URL')).hset("jrc_cc_public:#{@configuration.fetch('nonce')}:produced", job.provider_job_id, receipt.to_json)
  end
end
