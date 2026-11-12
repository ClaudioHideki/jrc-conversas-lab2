# frozen_string_literal: true
# Reuse all native synthetic DB/Redis guards and external-network blocking.
require File.join(ENV.fetch('GITHUB_WORKSPACE'), 'product/test/jrc_runtime/sidekiq_worker')
require_relative '../runtime_build/receipt'
class RuntimeReceiptRegressionWorker
  include Sidekiq::Job
  sidekiq_options queue: 'jrc_scout_fix_receipt', retry: false
  def perform(nonce)
    source = ENV.fetch('EXPECTED_PRODUCT_SHA')
    receipt = RuntimeSmokeReceipt.build(product_sha: source, nonce: nonce, pid: Process.pid)
    c = ActiveRecord::Base.connection
    raise 'Wrong owned database' unless c.select_value('SELECT current_database()') == 'jrc_runtime_compatibility_20261112_test'
    c.execute('INSERT INTO jrc_runtime_fix_receipts (nonce, details) VALUES (' + c.quote(nonce) + ', ' + c.quote(JSON.generate(receipt)) + '::jsonb)')
    Redis.new(url: ENV.fetch('REDIS_URL')).set('jrc:runtime:fix:' + nonce, JSON.generate(receipt), ex: 120)
  end
end
