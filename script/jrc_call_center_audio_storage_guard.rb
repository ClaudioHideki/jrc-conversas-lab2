# frozen_string_literal: true

require 'uri'
require 'pathname'

# Test harness only. Production continues to use the existing configured storage service.
class JrcContactCenter::SyntheticAudioStorageGuard
  DATABASES = %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic corporate_gratuity_disposable].freeze

  def self.call
    raise 'Exclusive synthetic audio database/Redis required' unless owned_database? && owned_redis?

    service = ActiveStorage::Blob.service
    disk = service.is_a?(ActiveStorage::Service::DiskService) && owned_root?(service.root)
    raise 'Institutional audio tests require this runner own local disk storage; no cloud fallback' unless disk
  end

  def self.owned_database?
    config = ActiveRecord::Base.connection_db_config
    Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
      config.configuration_hash[:host] == '127.0.0.1' && DATABASES.include?(config.database)
  end

  def self.owned_redis?
    redis = URI.parse(ENV.fetch('REDIS_URL'))
    redis.scheme == 'redis' && redis.host == '127.0.0.1' && redis.port == 6379 && redis.path == '/15'
  end

  def self.resolved(path)
    target = Pathname(path).expand_path
    ancestor = target.ascend.find(&:exist?)
    ancestor.realpath.join(target.relative_path_from(ancestor)).cleanpath.to_s
  end

  def self.owned_root?(root)
    target = resolved(root)
    paths = [Rails.root.join('tmp'), Rails.root.join('storage'), ENV.fetch('RUNNER_TEMP')]
    paths.any? do |path|
      owned = resolved(path)
      target == owned || target.start_with?(owned + File::SEPARATOR)
    end
  end
  private_class_method :owned_database?, :owned_redis?, :owned_root?, :resolved
end
