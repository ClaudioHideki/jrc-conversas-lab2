# frozen_string_literal: true

abort 'Exclusive synthetic runtime worker required' unless ENV['JRC_RUNTIME_CANDIDATE'] == '1' &&
                                                         ENV['RAILS_ENV'] == 'test' &&
                                                         ENV['POSTGRES_DATABASE'] == 'jrc_runtime_compatibility_20261112_test' &&
                                                         ENV['POSTGRES_HOST'] == '127.0.0.1' &&
                                                         ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/14'

require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)
require_relative '../../config/environment'

class JrcRuntimeCandidateWorker
  include Sidekiq::Job

  sidekiq_options queue: 'jrc_runtime_candidate_ci', retry: false

  def perform(token)
    raise ArgumentError, 'Synthetic token required' unless token.match?(/\A[0-9a-f]{32}\z/)

    result = { ruby: RUBY_VERSION, database: ActiveRecord::Base.connection.select_value('SELECT 1'),
               environment: Rails.env, database_name: ActiveRecord::Base.connection_db_config.database }
    Sidekiq.redis { |redis| redis.call('SET', "jrc:runtime:#{token}", result.to_json, 'EX', 120) }
  end
end
