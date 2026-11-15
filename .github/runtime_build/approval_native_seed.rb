require 'json'
require 'securerandom'
require 'open3'
require_relative 'approval_browser_fixture'

raise 'Hosted isolated runner required' unless ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
raise 'Production-like native runtime required' unless Rails.env.production?
sha, status = Open3.capture2('git', 'rev-parse', 'HEAD')
raise 'Wrong native source' unless status.success? && sha.strip == ENV.fetch('JRC_BROWSER_PRODUCT_SHA')
raise 'Wrong database host' unless ENV.fetch('POSTGRES_HOST') == '127.0.0.1'
raise 'Wrong database' unless ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_runtime_image_test'
redis = URI(ENV.fetch('REDIS_URL'))
raise 'Wrong isolated Redis' unless redis.host == '127.0.0.1' && redis.port == 6379 && redis.path == '/15'
raise 'Non-empty account database' unless Account.count.zero?
JrcApprovalBrowserFixture.build!(nonce: ENV.fetch('RUNTIME_SMOKE_NONCE'), product_sha: sha.strip,
                                output: ENV.fetch('JRC_BROWSER_CREDENTIALS'))
