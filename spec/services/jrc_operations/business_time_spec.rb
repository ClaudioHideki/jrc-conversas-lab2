require 'rails_helper'

RSpec.describe JrcOperations::BusinessTime do
  around do |example|
    Time.use_zone('America/Sao_Paulo') { example.run }
  end

  it 'uses elapsed minutes when business calendar is disabled' do
    start = Time.zone.parse('2026-10-02 17:30')
    expect(described_class.new(enabled: false).add_minutes(start, 120)).to eq(start + 120.minutes)
  end

  it 'skips weekends and honors configured business hours' do
    calendar = described_class.new(enabled: true, weekdays: [1, 2, 3, 4, 5], start: '08:00', end: '18:00')
    friday = Time.zone.parse('2026-10-02 17:30')
    expect(calendar.add_minutes(friday, 120)).to eq(Time.zone.parse('2026-10-05 09:30'))
  end

  it 'skips configured holidays' do
    calendar = described_class.new(enabled: true, weekdays: [1, 2, 3, 4, 5], start: '08:00', end: '18:00', holidays: ['2026-10-05'])
    friday = Time.zone.parse('2026-10-02 17:30')
    expect(calendar.add_minutes(friday, 120)).to eq(Time.zone.parse('2026-10-06 09:30'))
  end
end
