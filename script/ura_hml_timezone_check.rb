# Run inside the Rails image while the real Sidekiq process has explicitly
# loaded ura_hml_timezone.rb and is listening on ura_hml_timezone_probe:
# bundle exec rails runner script/ura_hml_timezone_check.rb
require_relative 'ura_hml_timezone'
require 'securerandom'

raise 'HML requires APP_TIME_ZONE=America/Sao_Paulo' unless ENV['APP_TIME_ZONE'] == 'America/Sao_Paulo'

run_id = SecureRandom.uuid
key = "#{UraHmlTimezoneProbe::KEY_PREFIX}#{run_id}"
redis = Redis.new(url: UraHmlTimezoneProbe::REDIS_URL)

begin
  rails = UraHmlTimezoneProbe.snapshot
  job_id = UraHmlTimezoneProbe::Job.perform_async(run_id)
  raise 'Sidekiq refused the timezone diagnostic job' unless job_id

  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
  evidence = nil
  loop do
    evidence = redis.get(key)
    break if evidence

    if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      raise 'Timed out waiting for real Sidekiq timezone evidence on ura_hml_timezone_probe'
    end

    sleep 0.1
  end

  sidekiq = JSON.parse(evidence)
  raise 'Timezone evidence does not match the enqueued Sidekiq job' unless sidekiq['sidekiq_server'] && sidekiq['job_id'] == job_id

  expected_zones = ['America/Sao_Paulo'] * 3
  { 'rails' => rails, 'sidekiq' => sidekiq }.each do |role, snapshot|
    unless snapshot.values_at('configured_zone', 'default_zone', 'zone') == expected_zones
      raise "#{role}: Rails timezone configuration is incorrect: #{JSON.generate(snapshot)}"
    end
    unless snapshot['utc_offset'] == -10_800 && snapshot['current'].end_with?('-03:00') && snapshot['current_utc'].end_with?('Z')
      raise "#{role}: Time.current or its UTC representation is incorrect: #{JSON.generate(snapshot)}"
    end
    unless Time.iso8601(snapshot['current']).utc == Time.iso8601(snapshot['current_utc'])
      raise "#{role}: application and UTC timestamps must describe the same instant"
    end
    unless snapshot['database_timezone'] == 'utc' && snapshot['system_tz'] == 'UTC' && snapshot['system_utc_offset'].zero?
      raise "#{role}: database storage and system timezone must remain UTC: #{JSON.generate(snapshot)}"
    end
  end

  puts JSON.pretty_generate('check' => 'ura_hml_timezone', 'run_id' => run_id, 'job_id' => job_id, 'rails' => rails, 'sidekiq' => sidekiq)
ensure
  redis.del(key)
  redis.close
end
