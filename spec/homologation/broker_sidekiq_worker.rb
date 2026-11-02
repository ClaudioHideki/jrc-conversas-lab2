# Laboratory entrypoint: boot Rails as client before requiring CLI, so general cron is not loaded.
abort 'LAB_ONLY_BEFORE_BOOT' unless ENV['RAILS_ENV'] == 'test' && ENV['POSTGRES_DATABASE'] == 'jrc_durable_review_test'
require File.expand_path('../../config/environment', __dir__)
require 'digest'
abort 'LAB_ONLY' unless Rails.env.test? && ActiveRecord::Base.connection_db_config.database == 'jrc_durable_review_test'
abort 'CRON_ALREADY_LOADED' if Sidekiq.server?
require 'sidekiq/cron/job'
Sidekiq::Cron::Job.define_singleton_method(:load_from_hash!) do |*_args, **_kwargs|
  raise 'GENERAL_CRON_DISABLED_IN_LAB'
end
ActiveJob::Base.queue_adapter = :sidekiq
JrcBroker::WebhookObligationJob.queue_name = 'broker_homologation_20261102'
module DurableLabTransport
  def fetch(url, **options)
    raise 'UNEXPECTED_LAB_TARGET' unless url == 'http://example.com'
    payload = JSON.parse(options.fetch(:body))
    delivery = options.fetch(:headers).fetch('X-Chatwoot-Delivery')
    raise 'INVALID_LAB_ID' unless delivery.match?(/\A[0-9a-f-]{36}\z/)
    account = Integer(payload.fetch('account').fetch('id'))
    hash = Digest::SHA256.hexdigest(options.fetch(:body))
    connection = ActiveRecord::Base.connection
    inserted = connection.exec_query("INSERT INTO jrc_lab_sidekiq_receipts(delivery_id,account_id,body_hash) VALUES(#{connection.quote(delivery)},#{account},#{connection.quote(hash)}) ON CONFLICT DO NOTHING RETURNING delivery_id")
    row = connection.exec_query("SELECT account_id,body_hash FROM jrc_lab_sidekiq_receipts WHERE delivery_id=#{connection.quote(delivery)}").first
    raise 'RECEIPT_CONFLICT' unless row['account_id'] == account && row['body_hash'] == hash
    if inserted.any? && ENV['LAB_KILL_AFTER_RECEIPT'] == '1'
      File.write('/tmp/sidekiq-commit-boundary.json', { delivery: delivery, receiverCommitted: true }.to_json)
      Process.kill('KILL', Process.pid)
    end
    nil
  end
end
SafeFetch.singleton_class.prepend(DurableLabTransport)
require 'sidekiq/cli'
cli = Sidekiq::CLI.instance
cli.parse(['-c', '1', '-q', 'broker_homologation_20261102', '-r', Rails.root.join('config/environment.rb').to_s])
cli.run
