require 'rails_helper'

RSpec.describe JrcHumanAssignment::AgentSchedule do
  let(:days) { (0..6).to_h { |day| [day.to_s, []] } }
  let(:shift) { days.merge('1' => [{ 'start' => '09:00', 'end' => '12:00' }, { 'start' => '13:00', 'end' => '18:00' }]) }

  it 'honors the inbox timezone, lunch and half-open shift boundaries' do
    calendar = described_class.new(shift)
    expect(calendar.open?(time: Time.iso8601('2026-11-09T12:00:00Z'), timezone: 'America/Sao_Paulo')).to be(true)
    expect(calendar.open?(time: Time.iso8601('2026-11-09T15:00:00Z'), timezone: 'America/Sao_Paulo')).to be(false)
    expect(calendar.open?(time: Time.iso8601('2026-11-09T16:00:00Z'), timezone: 'America/Sao_Paulo')).to be(true)
    expect(calendar.open?(time: Time.iso8601('2026-11-09T21:00:00Z'), timezone: 'America/Sao_Paulo')).to be(false)
    expect(calendar.open?(time: Time.iso8601('2026-11-09T11:00:00Z'), timezone: 'America/Sao_Paulo')).to be(false)
  end

  it 'carries overnight periods across the end of the week' do
    shift = days.merge('6' => [{ 'start' => '22:00', 'end' => '06:00' }])
    calendar = described_class.new(shift)
    expect(calendar.open?(time: Time.iso8601('2026-11-08T03:00:00Z'), timezone: 'UTC')).to be(true)
    expect(calendar.open?(time: Time.iso8601('2026-11-08T06:00:00Z'), timezone: 'UTC')).to be(false)
    expect(calendar.open?(time: Time.iso8601('2026-11-08T22:00:00Z'), timezone: 'UTC')).to be(false)
  end

  it 'inherits the inbox window when no individual schedule is configured' do
    expect(described_class.new(nil).open?(time: Time.current, timezone: 'UTC')).to be(true)
    expect(described_class.new(days).open?(time: Time.current, timezone: 'UTC')).to be(false)
  end

  it 'accepts touching periods and full days but rejects weekly overlap including midnight' do
    touching = days.merge('1' => [{ 'start' => '00:00', 'end' => '12:00' }, { 'start' => '12:00', 'end' => '24:00' }])
    expect { described_class.validate!('1' => touching) }.not_to raise_error
    overlap = days.merge('6' => [{ 'start' => '22:00', 'end' => '06:00' }], '0' => [{ 'start' => '05:00', 'end' => '09:00' }])
    expect { described_class.validate!('1' => overlap) }.to raise_error(ArgumentError)
  end

  it 'rejects incomplete weeks, invalid times, zero-length periods and noncanonical user IDs' do
    invalid = [nil, [], { '01' => shift }, { '1' => shift.except('0') },
               { '1' => days.merge('1' => [{ 'start' => '24:00', 'end' => '08:00' }]) },
               { '1' => days.merge('1' => [{ 'start' => '08:00', 'end' => '08:00' }]) },
               { '1' => days.merge('1' => [{ 'start' => '8:00', 'end' => '09:00' }]) }]
    invalid.each { |value| expect { described_class.validate!(value) }.to raise_error(ArgumentError) }
  end
end
