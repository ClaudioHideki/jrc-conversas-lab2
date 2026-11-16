# frozen_string_literal: true
# Additional image-only checks; the approved probe/worker/receipt remain byte-identical.
require 'json'
require 'digest'
require_relative 'receipt'
raise 'Synthetic production image required' unless Rails.env.production? &&
  ENV.fetch('POSTGRES_DATABASE') == 'jrc_runtime_image_test' &&
  ActiveRecord::Base.connection.select_value('SELECT current_database()') == 'jrc_runtime_image_test'
source = ENV.fetch('RUNTIME_PRODUCT_SHA')
nonce = ENV.fetch('RUNTIME_SMOKE_NONCE')
raise 'Wrong immutable image' unless File.read('/app/.git_sha').strip == source
raise 'Wrong owned Redis' unless URI(ENV.fetch('REDIS_URL')).host.start_with?('jrc-runtime-')
report = { phase: ARGV.fetch(0), product_sha: source, passed: false }
begin
  case ARGV.fetch(0)
  when 'scout'
    %w[whatsapp_retry_attempts jrc_service_desk_report_exports].each do |table|
      raise 'Recent migration missing from synthetic image database' unless ActiveRecord::Base.connection.data_source_exists?(table)
    end
    require 'scout_apm'
    raise 'Wrong official Scout version' unless Gem.loaded_specs.fetch('scout_apm').version.to_s == '5.7.0'
    raise 'Native monitoring disabled' unless ScoutApm::Instruments::Allocations::ENABLED == true
    before = ScoutApm::Instruments::Allocations.count
    objects = Array.new(2000) { String.new('synthetic image Scout metric') }
    delta = ScoutApm::Instruments::Allocations.count - before
    raise 'Scout allocation hook failed' unless delta >= objects.size
    extension = $LOADED_FEATURES.find { |path| path.end_with?('/allocations.so') }
    raise 'Native Scout extension missing' unless extension && File.file?(extension)
    report.merge!(scout: '5.7.0', ruby: RUBY_VERSION, allocation_monitoring: true, allocation_delta: delta,
                  extension_sha256: Digest::SHA256.file(extension).hexdigest,
                  external_telemetry_homologated: false)
  when 'worker_pid_one'
    raw = Redis.new(url: ENV.fetch('REDIS_URL')).get('jrc:runtime:receipt:' + nonce)
    raise 'Worker receipt missing' unless raw
    data = JSON.parse(raw)
    c = ActiveRecord::Base.connection
    saved = c.select_value('SELECT details::text FROM jrc_runtime_smoke_receipts WHERE nonce=' + c.quote(nonce))
    RuntimeSmokeReceipt.verify!(data: data, persisted: saved && JSON.parse(saved), product_sha: source, nonce: nonce)
    raise 'Image Sidekiq is not PID 1' unless data.fetch('pid') == 1
    report.merge!(actual_sidekiq_pid: data.fetch('pid'), postgres_redis_receipts_equal: true)
  else
    raise 'Unknown extra phase'
  end
  report[:passed] = true
ensure
  File.write(File.join(ENV.fetch('RUNTIME_SMOKE_OUTPUT'), 'extra-' + ARGV.fetch(0) + '.json'), JSON.pretty_generate(report))
  puts JSON.generate(report)
end
