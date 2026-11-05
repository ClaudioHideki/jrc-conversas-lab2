# Diagnostic support loaded explicitly by the HML Sidekiq command:
# bundle exec sidekiq -r ./script/ura_hml_timezone.rb -q ura_hml_timezone_probe
# This file is deliberately outside the application's autoload paths.
require 'rails'
require 'sidekiq/rails'
require_relative '../config/environment'
require 'json'
require 'socket'

module UraHmlTimezoneProbe
  QUEUE = 'ura_hml_timezone_probe'.freeze
  KEY_PREFIX = 'ura_hml:timezone_probe:'.freeze
  TTL_SECONDS = 180
  REDIS_URL = ENV['URA_HML_TIMEZONE_REDIS_URL'].presence&.freeze
  raise ArgumentError, 'URA_HML_TIMEZONE_REDIS_URL is required and must point to the isolated evidence Redis database' unless REDIS_URL

  def self.snapshot
    now = Time.current
    {
      'hostname' => Socket.gethostname,
      'rails_env' => Rails.env.to_s,
      'pid' => Process.pid,
      'thread_id' => Thread.current.object_id,
      'configured_zone' => Rails.application.config.time_zone,
      'default_zone' => Time.zone_default.name,
      'zone' => Time.zone.name,
      'current' => now.iso8601(6),
      'current_utc' => now.utc.iso8601(6),
      'utc_offset' => now.utc_offset,
      'database_timezone' => ActiveRecord.default_timezone.to_s,
      'system_tz' => ENV.fetch('TZ', nil),
      'system_utc_offset' => Time.now.getlocal.utc_offset
    }
  end
end

# A native Sidekiq job intentionally avoids ActiveJob's serialized timezone,
# which could otherwise conceal an incorrectly configured worker default.
class UraHmlTimezoneProbe::Job
  include Sidekiq::Job
  sidekiq_options queue: UraHmlTimezoneProbe::QUEUE, retry: false

  def perform(run_id)
    raise 'Timezone evidence must be produced by a real Sidekiq server' unless Sidekiq.server?

    evidence = UraHmlTimezoneProbe.snapshot.merge('sidekiq_server' => true, 'job_id' => jid)
    redis = Redis.new(url: UraHmlTimezoneProbe::REDIS_URL)
    redis.set("#{UraHmlTimezoneProbe::KEY_PREFIX}#{run_id}", JSON.generate(evidence), ex: UraHmlTimezoneProbe::TTL_SECONDS)
  ensure
    redis&.close
  end
end
