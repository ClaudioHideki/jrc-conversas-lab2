# frozen_string_literal: true
require_relative 'native_worker'
require 'timeout'
require 'securerandom'
require 'json'
require 'scout_apm'
raise 'Scout not loaded at reviewed version' unless Gem.loaded_specs.fetch('scout_apm').version.to_s == '5.7.0'
raise 'Scout allocations disabled' unless ScoutApm::Instruments::Allocations::ENABLED
before = ScoutApm::Instruments::Allocations.count
objects = Array.new(1000) { String.new('native Scout regression') }
raise 'Scout allocations not functioning' unless ScoutApm::Instruments::Allocations.count - before >= objects.size
source = ENV.fetch('EXPECTED_PRODUCT_SHA')
nonce = SecureRandom.hex(16)
c = ActiveRecord::Base.connection
c.execute('CREATE TABLE jrc_runtime_fix_receipts (nonce varchar PRIMARY KEY, details jsonb NOT NULL)')
log = File.join(ENV.fetch('RUNNER_TEMP'), 'receipt-sidekiq.log')
worker = File.expand_path('native_worker.rb', __dir__)
pid = Process.spawn('bundle', 'exec', 'sidekiq', '-r', worker, '-q', 'jrc_scout_fix_receipt', '-c', '1', out: log, err: [:child, :out])
begin
  jid = RuntimeReceiptRegressionWorker.perform_async(nonce)
  raise 'Enqueue missing' unless jid.is_a?(String)
  redis = Redis.new(url: ENV.fetch('REDIS_URL'))
  raw = nil
  Timeout.timeout(60) do
    until raw
      raw = redis.get('jrc:runtime:fix:' + nonce)
      sleep 0.25 unless raw
    end
  end
  data = JSON.parse(raw)
  saved = c.select_value('SELECT details::text FROM jrc_runtime_fix_receipts WHERE nonce=' + c.quote(nonce))
  RuntimeSmokeReceipt.verify!(data: data, persisted: saved && JSON.parse(saved), product_sha: source, nonce: nonce)
  raise 'Worker did not execute in actual child process' unless data.fetch('pid') == pid && pid != Process.pid
  File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'receipt-native.json'), JSON.pretty_generate(
    passed: true, product_sha: source, scout_version: ScoutApm::VERSION, allocation_monitoring: true,
    actual_sidekiq_pid: pid, verifier_pid: Process.pid, postgres_redis_receipts_equal: true))
ensure
  if Process.waitpid(pid, Process::WNOHANG).nil?
    Process.kill('TERM', pid)
    Timeout.timeout(20) { Process.waitpid(pid) }
  end
end
