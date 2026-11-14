# Actual shared native fixture, only in the owned disposable image database.
require 'json'
require 'securerandom'
require_relative 'approval_browser_fixture'
raise 'Wrong immutable image' unless File.read('/app/.git_sha').strip == ENV.fetch('RUNTIME_PRODUCT_SHA')
raise 'Wrong owned database' unless ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_runtime_image_test'
raise 'Wrong owned Redis' unless URI(ENV.fetch('REDIS_URL')).host.start_with?('jrc-runtime-')
nonce=ENV.fetch('RUNTIME_SMOKE_NONCE')
raise 'Wrong nonce' unless nonce.match?(/\A[0-9a-f]{32}\z/)
JrcApprovalBrowserFixture.build!(nonce: nonce, product_sha: ENV.fetch('RUNTIME_PRODUCT_SHA'),
 output: File.join(ENV.fetch('RUNTIME_SMOKE_OUTPUT'),'browser-synthetic-credentials.private'))
