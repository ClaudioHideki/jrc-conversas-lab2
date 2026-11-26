# frozen_string_literal: true

# Test harness only. Production jobs and business commands remain unchanged.
# Route exactly two native job classes for four nonce-owned synthetic accounts;
# every other class/account retains its original test adapter and queue.
require 'json'
require 'digest'
require 'redis'

module SyntheticPublicEndingQueue
  JOB_CLASSES = %w[JrcContactCenter::EndingActionsJob JrcContactCenter::EndingDestinationJob].freeze
  DATABASE = 'jrc_sd_bc_portal_concurrency_20261025_test'
  MARKER = 'jrc_cc_owned_public_queue_nonce'

  def self.configuration!
    validate_environment!
    values = read_control!
    validate_control!(values)
    validate_runtime!(values)
    values.freeze
  end

  def self.validate_environment!
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
            ENV['POSTGRES_HOST'] == '127.0.0.1' && ENV['POSTGRES_DATABASE'] == DATABASE &&
            ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    raise 'Owned disposable public ending environment required' unless owned
  end

  def self.read_control!
    filename = ENV.fetch('JRC_CC_PUBLIC_QUEUE_CONTROL')
    raise 'Owned temporary queue control required' unless filename.match?(%r{\A/tmp/jrc-cc-public-ending-[0-9a-f]{24}\.private\z})
    raise 'Bounded private queue control required' unless File.file?(filename) && File.size(filename).between?(1, 8192)
    raise 'Private queue control permissions required' unless File.stat(filename).mode.nobits?(0o077)

    JSON.parse(File.binread(filename))
  end

  def self.validate_control!(values)
    fields = %w[nonce queue source_sha account_ids]
    raise 'Exact queue control fields required' unless values.is_a?(Hash) && values.keys.sort == fields.sort
    raise 'Owned nonce required' unless values['nonce'].is_a?(String) && values['nonce'].match?(/\A[0-9a-f]{24}\z/)
    raise 'Nonce queue mismatch' unless values['queue'] == "jrc_cc_public_#{values.fetch('nonce')}"

    validate_source_revision!(values.fetch('source_sha'))

    validate_accounts_shape!(values['account_ids'])
  end

  def self.validate_source_revision!(value)
    raise 'Exact source revision required' unless value == ENV.fetch('GITHUB_SHA') && value.match?(/\A[0-9a-f]{40}\z/)
  end

  def self.validate_accounts_shape!(ids)
    valid_ids = ids.is_a?(Array) && ids.length == 4 && ids.uniq.length == 4 && ids.all? { |id| id.is_a?(Integer) && id.positive? }
    raise 'Four distinct owned synthetic accounts required' unless valid_ids
  end

  def self.validate_runtime!(values)
    validate_connections!
    validate_workspace!(values)
    validate_owned_accounts!(values)
  end

  def self.validate_connections!
    config = ApplicationRecord.connection_db_config
    current = ApplicationRecord.connection.current_database
    raise 'Unexpected native PostgreSQL connection' unless config.configuration_hash[:host] == '127.0.0.1' && current == DATABASE

    info = Redis.new(url: ENV.fetch('REDIS_URL')).call('CLIENT', 'INFO')
    raise 'Unexpected Redis database' unless info.split.include?('db=15')
  end

  def self.validate_workspace!(values)
    workspace = File.realpath(ENV.fetch('GITHUB_WORKSPACE'))
    raise 'Unexpected native application directory' unless Rails.root.realpath.to_s == workspace

    head = IO.popen(%w[git rev-parse HEAD], &:read).strip
    raise 'Source checkout mismatch' unless head == values.fetch('source_sha')
  end

  def self.validate_owned_accounts!(values)
    accounts = Account.where(id: values.fetch('account_ids')).to_a
    raise 'Synthetic accounts missing' unless accounts.length == 4

    accounts.each do |account|
      unless account.name.start_with?('SYNTHETIC ') && account.custom_attributes[MARKER] == values.fetch('nonce')
        raise 'Account queue ownership mismatch'
      end
    end
  end

  def self.expected_arguments?(arguments, configuration)
    arguments.is_a?(Array) && arguments.length == 2 && arguments.all? { |id| id.is_a?(Integer) && id.positive? } &&
      configuration.fetch('account_ids').include?(arguments.first)
  end

  def self.install!
    configuration = configuration!
    JOB_CLASSES.each do |name|
      job = name.constantize
      previous = job.queue_adapter
      raise 'Owned queue was already installed' if previous.is_a?(Adapter)
      raise 'Preserve the existing isolated Rails test adapter for all unrelated jobs' unless previous.is_a?(ActiveJob::QueueAdapters::TestAdapter)

      job.queue_adapter = Adapter.new(previous, configuration)
    end
    configuration
  end
end

require_relative 'owned_public_ending_adapter'
