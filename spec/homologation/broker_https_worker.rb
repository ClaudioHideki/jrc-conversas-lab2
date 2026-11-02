# Real Sidekiq and real production SafeFetch. No transport method is replaced.
require_relative 'broker_https_harness'
require 'net/http'
runtime = BrokerHttpsHarness.runtime!(ENV)
root = File.expand_path('../..', __dir__)
require File.join(root, 'config/environment')
abort 'RAILS_TEST_DATABASE_MISMATCH' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == runtime.fetch('database')
abort 'CRON_ALREADY_LOADED' if Sidekiq.server?
abort 'SAFE_FETCH_MUST_BE_REAL' unless SafeFetch.method(:fetch).source_location.first == File.join(root, 'lib/safe_fetch.rb')
require 'sidekiq/cron/job'
Sidekiq::Cron::Job.define_singleton_method(:load_from_hash!) { |*_args, **_kwargs| raise 'GENERAL_CRON_DISABLED_IN_HTTPS_LAB' }
ActiveJob::Base.queue_adapter = :sidekiq
JrcBroker::WebhookObligationJob.queue_name = runtime.fetch('queue')
JrcBroker::WebhookRecoveryJob.queue_name = runtime.fetch('queue')
directory = runtime.fetch('directory')
key = runtime.fetch('key')
manifest = JSON.parse(File.read(File.join(directory, 'manifest.json')))
BrokerHttpsHarness.contexts!(manifest.fetch('contexts'))
context = manifest.fetch('contexts').find { |item| item.fetch('key') == key }
abort 'FIXTURE_TARGET_CHANGED' unless context.fetch('database') == runtime.fetch('database')
log = File.open(File.join(directory, "worker_#{key}.log"), 'a', 0o600)
$stdout.reopen(log)
$stderr.reopen(log)
$stdout.sync = true
$stderr.sync = true
scope_fields = %w[account_id inbox_id message_id delivery_id integration_id instance_id].freeze
monitor = Thread.new do
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 180
  loop do
    stop_file = File.join(directory, 'stop_requested.json')
    if File.exist?(stop_file) && JSON.parse(File.read(stop_file))['run_id'] == manifest.fetch('run_id')
      Process.kill('TERM', Process.pid)
      break
    end
    raise 'HTTPS_LAB_WORKER_TIMEOUT' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

    row = JrcBrokerWebhookObligation.uncached { JrcBrokerWebhookObligation.find(context.fetch('obligation_id')) }
    raise 'HTTPS_LAB_OBLIGATION_SCOPE_CHANGED' unless scope_fields.all? { |name| row.public_send(name) == context.fetch(name) }

    snapshot = row.attributes.slice('id', 'account_id', 'inbox_id', 'message_id', 'delivery_id', 'state', 'attempts', 'lease_token', 'lease_until',
                                    'last_error_code')
    snapshot['worker_pid'] = Process.pid
    snapshot['queue'] = runtime.fetch('queue')
    snapshot['rails_version'] = Rails.version
    snapshot['sidekiq_version'] = Sidekiq::VERSION
    snapshot['safe_fetch_source'] = 'lib/safe_fetch.rb'
    BrokerHttpsHarness.write_json!(directory, "worker_#{key}_state.json", snapshot)
    if ENV['BROKER_HTTPS_KILL_ARMED'] == '1' && row.state == 'running'
      uri = URI("#{runtime.fetch('origin')}/_lab/kill/#{key}")
      request = Net::HTTP::Get.new(uri)
      request['X-Lab-Control'] = manifest.fetch('control_token')
      response = Net::HTTP.start(
        uri.host, uri.port,
        use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_PEER,
        ca_file: runtime.fetch('ca_file'), open_timeout: 1, read_timeout: 1
      ) { |http| http.request(request) }
      barrier = JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
      if barrier && barrier['kill'] == true && barrier['run_id'] == manifest.fetch('run_id') &&
         barrier['delivery_id'] == row.delivery_id && barrier['upstream_status'] == 200 &&
         barrier.dig('counts', 'observations') == 1 && barrier.dig('counts', 'reply_jobs') == 1
        BrokerHttpsHarness.write_json!(directory, "worker_#{key}_killed.json", snapshot.merge('receiver_committed' => true, 'barrier' => barrier))
        Process.kill('KILL', Process.pid)
      end
    end
    target = ENV.fetch('BROKER_HTTPS_STOP_AT', 'delivered')
    if row.state == target && row.attempts.positive?
      BrokerHttpsHarness.write_json!(directory, "worker_#{key}_done.json", snapshot)
      Process.kill('TERM', Process.pid)
      break
    end
    sleep 0.1
  end
rescue StandardError => e
  BrokerHttpsHarness.write_json!(directory, "worker_#{key}_error.json", { 'error_class' => e.class.name, 'code' => e.message })
  Process.kill('TERM', Process.pid)
end
require 'sidekiq/cli'
cli = Sidekiq::CLI.instance
cli.parse(['-c', '1', '-q', runtime.fetch('queue'), '-r', File.join(root, 'config/environment.rb')])
cli.run
monitor.join(1)
