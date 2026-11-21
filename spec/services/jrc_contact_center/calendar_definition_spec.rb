require 'rails_helper'

RSpec.describe JrcContactCenter::CalendarDefinition do
  let(:attributes) do
    { 'name' => 'SYNTHETIC internal hours', 'description' => 'SYNTHETIC local calendar only', 'timezone' => 'America/Sao_Paulo',
      'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['08:00', '12:00'], ['13:00', '17:00']] : []] },
      'holidays' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC selected date', 'kind' => 'internal', 'type' => 'movable' }],
      'exceptions' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC explicit duty', 'intervals' => [['10:00', '11:00']] }] }
  end

  it 'uses the native interval calculator and explicit exception before holiday before weekly' do
    calendar = described_class.new(attributes)
    expect(calendar.preview('2026-11-23')).to include('precedence' => 'exception', 'intervals' => [['10:00', '11:00']], 'working_seconds' => 3600)
    expect(calendar.conditions.fetch('format')).to eq(JrcServiceDesk::SnapshotCalendar::VERSION)
    expect(calendar.preview('2026-11-24')).to include('precedence' => 'weekly', 'working_seconds' => 28_800)
    expect(calendar.preview('2026-11-22')).to include('precedence' => 'weekly', 'working_seconds' => 0)
    expect(calendar.preview('2026-11-23')).to include('local_only' => true, 'pabx_confirmed' => false)
  end

  it 'allows an explicitly closed exception even on a holiday and never restores ordinary working hours' do
    attributes.fetch('exceptions').first['intervals'] = []
    result = described_class.new(attributes).preview('2026-11-23')
    expect(result).to include('precedence' => 'exception', 'intervals' => [], 'working_seconds' => 0)
  end

  it 'closes a configured holiday without inferring another date, locality or recurrence' do
    attributes['exceptions'] = []
    calendar = described_class.new(attributes)
    expect(calendar.preview('2026-11-23')).to include('precedence' => 'holiday', 'intervals' => [], 'working_seconds' => 0)
    expect(calendar.preview('2027-11-23')).to include('precedence' => 'weekly', 'working_seconds' => 28_800)
    expect(calendar.values.fetch('holidays').first).to include('kind' => 'internal', 'type' => 'movable')
  end

  it 'keeps the admitted snapshot independent from mutable caller input, public values and returned interval arrays' do
    calendar = described_class.new(attributes)
    attributes.fetch('weekly').fetch('2').clear
    exposed = calendar.values
    exposed.fetch('weekly').fetch('2').clear
    native = calendar.conditions
    native.fetch('weekly').fetch('2').clear
    result = calendar.preview('2026-11-23')
    result.fetch('intervals').clear
    expect(calendar.preview('2026-11-24').fetch('working_seconds')).to eq(28_800)
    expect(calendar.preview('2026-11-23').fetch('intervals')).to eq([['10:00', '11:00']])
  end

  {
    'a missing explicit timezone' => ->(data) { data['timezone'] = '' },
    'an unknown timezone' => ->(data) { data['timezone'] = 'SYNTHETIC/Unknown' },
    'a noncanonical holiday date' => ->(data) { data.fetch('holidays').first['date'] = '23/11/2026' },
    'an impossible date' => ->(data) { data.fetch('holidays').first['date'] = '2026-02-30' },
    'an invented holiday category' => ->(data) { data.fetch('holidays').first['kind'] = 'automatic_provider' },
    'an invented recurrence formula' => ->(data) { data.fetch('holidays').first['type'] = 'easter_plus_unknown' },
    'a missing weekday' => ->(data) { data.fetch('weekly').delete('7') },
    'overlapping ordinary intervals' => ->(data) { data.fetch('weekly')['1'] = [['08:00', '12:00'], ['11:00', '17:00']] },
    'overlapping exception intervals' => ->(data) { data.fetch('exceptions').first['intervals'] = [['08:00', '12:00'], ['11:00', '17:00']] },
    'an overnight pair instead of explicit dates' => ->(data) { data.fetch('exceptions').first['intervals'] = [['22:00', '06:00']] },
    'duplicate exception dates' => ->(data) { data.fetch('exceptions') << data.fetch('exceptions').first.deep_dup },
    'duplicate holiday dates' => ->(data) { data.fetch('holidays') << data.fetch('holidays').first.deep_dup },
    'false instead of a holiday collection' => ->(data) { data['holidays'] = false },
    'foreign authority fields' => ->(data) { data['account_id'] = '999' }
  }.each do |description, change|
    it "rejects #{description} instead of inventing a default or dropping malformed values" do
      change.call(attributes)
      expect { described_class.new(attributes) }.to raise_error(JrcContactCenter::OperationError, 'invalid_contact_center_calendar')
    end
  end

  it 'rejects a nonexistent daylight-saving interval instead of silently choosing an offset' do
    attributes['timezone'] = 'America/New_York'
    attributes.fetch('weekly')['7'] = [['02:15', '03:15']]
    calendar = described_class.new(attributes)
    expect { calendar.preview('2026-03-08') }.to raise_error(JrcContactCenter::OperationError, 'invalid_contact_center_calendar')
  end

  it 'preserves the native refusal to fabricate a deadline for an entirely unconfigured calendar' do
    attributes['weekly'] = (1..7).to_h { |day| [day.to_s, []] }
    attributes['exceptions'] = []
    expect { described_class.new(attributes) }.to raise_error(JrcContactCenter::OperationError, 'invalid_contact_center_calendar')
  end
end
