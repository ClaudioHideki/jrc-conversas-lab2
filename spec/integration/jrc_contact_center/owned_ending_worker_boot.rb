# frozen_string_literal: true

# Test witness only. Real Sidekiq/Redis/PostgreSQL, never a provider stub or a
# replacement business receipt. This file is not part of application autoloading.
require 'json'
require 'digest'
require 'sidekiq'
require 'sidekiq/cli'
require 'redis'
require 'webmock'

owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && ENV['RAILS_ENV'] == 'test' &&
        ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == 'corporate_gratuity_disposable' &&
        ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
raise 'Owned disposable ending worker required' unless owned
raise 'Owned ending worker nonce required' unless ENV.fetch('JRC_CC_BROKER_NONCE').match?(/\A[0-9a-f]{24}\z/)

WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)
require File.expand_path('../../../config/environment', __dir__)

class SyntheticEndingWorkerWitness
  def call(_worker, job, queue)
    raise 'Unexpected queue in owned worker' unless queue == ENV.fetch('JRC_CC_BROKER_QUEUE')

    arguments = job.dig('args', 0, 'arguments')
    valid = job.dig('args', 0, 'job_class') == 'JrcContactCenter::EndingActionsJob' && arguments.is_a?(Array) &&
            arguments.length == 2 && arguments.all? { |id| id.is_a?(Integer) && id.positive? }
    raise 'Unexpected job in owned worker' unless valid && arguments.first.to_s == ENV.fetch('JRC_CC_BROKER_ACCOUNT_ID')

    yield
    data = { jid: job.fetch('jid'), account_id: arguments.first, qualification_id: arguments.last,
             worker_pid: Process.pid, source_sha: ENV.fetch('GITHUB_SHA'),
             witness_sha256: Digest::SHA256.file(__FILE__).hexdigest }
    Redis.new(url: ENV.fetch('REDIS_URL')).hset("jrc_cc_broker:#{ENV.fetch('JRC_CC_BROKER_NONCE')}:acks", job.fetch('jid'), data.to_json)
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware { |chain| chain.add(SyntheticEndingWorkerWitness) }
  config.on(:startup) do
    database = ApplicationRecord.connection_db_config
    raise 'Unexpected worker database' unless Rails.env.test? && database.configuration_hash[:host] == '127.0.0.1' &&
                                              ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Unexpected worker queue' unless config.queues.uniq == [ENV.fetch('JRC_CC_BROKER_QUEUE')]
    workspace = File.realpath(ENV.fetch('GITHUB_WORKSPACE'))
    raise 'Unexpected worker source directory' unless Rails.root.realpath.to_s == workspace

    head = IO.popen(['git', 'rev-parse', 'HEAD'], &:read).strip
    raise 'Unexpected worker source revision' unless head == ENV.fetch('GITHUB_SHA') && head.match?(/\A[0-9a-f]{40}\z/)

    marker = Account.find(ENV.fetch('JRC_CC_BROKER_ACCOUNT_ID')).custom_attributes['jrc_cc_owned_broker_nonce']
    raise 'Worker account ownership mismatch' unless marker == ENV.fetch('JRC_CC_BROKER_NONCE')

    connection = Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }
    raise 'Unexpected worker Redis database' unless connection.split.include?('db=15')
  end
end

load Gem.bin_path('sidekiq', 'sidekiq')
