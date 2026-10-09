require 'timeout'

module JrcServiceDeskConcurrency
  extend ActiveSupport::Concern

  DISPOSABLE_DATABASES = %w[jrc_rel_sd_candidate_test jrc_rel_sd_r2_concurrency_test jrc_rel_sd_r345_concurrency_test].freeze

  included do
    around do |example|
      if service_desk_concurrency_enabled?
        example.run
      else
        skip 'Opt-in requires the explicitly named disposable PostgreSQL test database'
      end
    end
  end

  def service_desk_concurrency_enabled?
    Rails.env.test? && ENV['JRC_SD_CONCURRENCY'] == '1' &&
      ActiveRecord::Base.connection.adapter_name == 'PostgreSQL' &&
      DISPOSABLE_DATABASES.include?(ENV.fetch('POSTGRES_DATABASE', nil)) &&
      ActiveRecord::Base.connection_db_config.database == ENV.fetch('POSTGRES_DATABASE', nil)
  end

  def concurrently(operations)
    raise 'Concurrent fixtures must be committed' if ActiveRecord::Base.connection.transaction_open?

    gate = Queue.new
    outcomes = Queue.new
    workers = operations.map { |operation| Thread.new { concurrent_operation(gate, outcomes, operation) } }
    operations.size.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    Array.new(operations.size) { outcomes.pop }
  ensure
    cleanup_concurrent_workers(workers)
  end

  def concurrent_operation(gate, outcomes, operation)
    ActiveRecord::Base.connection_pool.with_connection do
      gate.pop
      outcomes << operation.call
    rescue StandardError => e
      outcomes << e
    end
  end

  def cleanup_concurrent_workers(workers)
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end
