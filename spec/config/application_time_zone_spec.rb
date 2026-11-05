require 'spec_helper'
require 'json'
require 'open3'
require 'rbconfig'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Application time zone configuration' do
  # rubocop:enable RSpec/DescribeClass
  let(:application_root) { File.expand_path('../..', __dir__) }
  let(:time_zone) { 'America/Sao_Paulo' }
  let(:environment) { { 'RAILS_ENV' => 'test', 'APP_TIME_ZONE' => time_zone, 'TZ' => 'UTC' } }
  let(:probe) do
    <<~RUBY
      require './config/application'
      require 'active_support/testing/time_helpers'
      require 'json'

      # Exercise the real Rails initializer without booting unrelated application
      # integrations. The script/ura_hml_timezone* probe covers full runtimes.
      Rails.application.initializers.find { |initializer| initializer.name == 'active_support.initialize_time_zone' }.run(Rails.application)

      Object.new.extend(ActiveSupport::Testing::TimeHelpers).travel_to(Time.utc(2026, 11, 4, 2, 30, 0)) do
        puts 'TIME_ZONE_PROBE=' + JSON.generate(
          configured_zone: Rails.application.config.time_zone,
          zone: Time.zone.name,
          current: Time.current.iso8601,
          current_epoch: Time.current.to_i,
          utc: Time.current.utc.iso8601,
          system_utc_offset: Time.now.utc_offset,
          database_timezone: ActiveRecord.default_timezone,
          new_thread_zone: Thread.new { Time.zone.name }.value
        )
      end
    RUBY
  end
  let(:result) { Open3.capture3(environment, RbConfig.ruby, '-e', probe, chdir: application_root) }
  let(:stdout) { result[0] }
  let(:stderr) { result[1] }
  let(:status) { result[2] }
  let(:evidence) { JSON.parse(stdout.lines.find { |line| line.start_with?('TIME_ZONE_PROBE=') }.delete_prefix('TIME_ZONE_PROBE=')) }

  it 'applies the IANA zone to Rails time, including new worker threads, while keeping UTC storage and system time' do
    expect(status.success?).to be(true), stderr
    expect(evidence).to include(
      'configured_zone' => 'America/Sao_Paulo',
      'zone' => 'America/Sao_Paulo',
      'current' => '2026-11-03T23:30:00-03:00',
      'current_epoch' => 1_793_759_400,
      'utc' => '2026-11-04T02:30:00Z',
      'system_utc_offset' => 0,
      'database_timezone' => 'utc',
      'new_thread_zone' => 'America/Sao_Paulo'
    )
  end

  context 'without an APP_TIME_ZONE setting' do
    let(:time_zone) { nil }

    it 'preserves UTC as the installation default' do
      expect(status.success?).to be(true), stderr
      expect(evidence).to include('zone' => 'UTC', 'current' => '2026-11-04T02:30:00Z', 'database_timezone' => 'utc')
    end
  end

  context 'with another IANA zone' do
    let(:time_zone) { 'Asia/Tokyo' }

    it 'uses the configured zone rather than hardcoding the HML offset' do
      expect(status.success?).to be(true), stderr
      expect(evidence).to include('zone' => 'Asia/Tokyo', 'current' => '2026-11-04T11:30:00+09:00')
    end
  end

  ['Invalid/Timezone', 'Brasilia', ''].each do |invalid_zone|
    context "with invalid IANA configuration #{invalid_zone.inspect}" do
      let(:time_zone) { invalid_zone }

      it 'fails boot with an actionable APP_TIME_ZONE error' do
        expect(status.success?).to be(false)
        expect(stderr).to include('APP_TIME_ZONE', 'IANA')
      end
    end
  end
end
