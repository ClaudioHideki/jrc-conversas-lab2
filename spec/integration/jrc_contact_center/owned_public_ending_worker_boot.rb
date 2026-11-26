# frozen_string_literal: true

# Exclusive real Sidekiq worker for a nonce queue; not application autoloading.
require 'sidekiq'
require 'sidekiq/cli'
require 'webmock'

WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)
require File.expand_path('../../../config/environment', __dir__)
require_relative 'owned_public_ending_queue'

configuration = SyntheticPublicEndingQueue.install!

class SyntheticPublicEndingWorkerWitness
  def initialize(configuration)
    @configuration = configuration
  end

  def call(_worker, job, queue)
    arguments, name = validate_job!(job, queue)
    yield
    receipt = native_receipt(job, queue, arguments, name)
    Redis.new(url: ENV.fetch('REDIS_URL')).hset("jrc_cc_public:#{@configuration.fetch('nonce')}:acks", job.fetch('jid'), receipt.to_json)
  end

  private

  def validate_job!(job, queue)
    arguments = job.dig('args', 0, 'arguments')
    name = job.dig('args', 0, 'job_class')
    valid = queue == @configuration.fetch('queue') && SyntheticPublicEndingQueue::JOB_CLASSES.include?(name) &&
            SyntheticPublicEndingQueue.expected_arguments?(arguments, @configuration)
    raise 'Unexpected job in exclusive browser worker' unless valid

    [arguments, name]
  end

  def native_receipt(job, queue, arguments, name)
    { jid: job.fetch('jid'), job_class: name, account_id: arguments.first, record_id: arguments.last,
      worker_pid: Process.pid, source_sha: @configuration.fetch('source_sha'), queue: queue,
      database: ApplicationRecord.connection.current_database,
      postgres_backend_pid: ApplicationRecord.connection.raw_connection.backend_pid,
      redis_database: Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }.split.include?('db=15') ? 15 : nil,
      witness_sha256: Digest::SHA256.file(__FILE__).hexdigest }
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware { |chain| chain.add(SyntheticPublicEndingWorkerWitness, configuration) }
  config.on(:startup) do
    SyntheticPublicEndingQueue.configuration!
    raise 'Worker may consume only its nonce queue' unless config.queues.uniq == [configuration.fetch('queue')]
  end
end

load Gem.bin_path('sidekiq', 'sidekiq')
