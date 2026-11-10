require 'rails_helper'

RSpec.describe JrcRelationship::OperationalPeriod do
  it 'preserves an absent period and does not silently ignore an end-only date' do
    expect(described_class.call({})).to be_nil
    expect(described_class.call(from: '', to: '')).to be_nil
    expect { described_class.call(to: '2026-10-01') }.to raise_error(ArgumentError, /start date/)
  end

  it 'preserves the legacy single-day input and account-local inclusive boundaries' do
    Time.use_zone('America/Sao_Paulo') do
      period = described_class.call(from: '2026-10-01')
      expect(period.cover?(Time.utc(2026, 10, 1, 3))).to be(true)
      expect(period.cover?(Time.utc(2026, 10, 2, 2, 59, 59))).to be(true)
      expect(period.cover?(Time.utc(2026, 10, 1, 2, 59, 59))).to be(false)
      expect(period.cover?(Time.utc(2026, 10, 2, 3))).to be(false)
      expect(described_class.call(from: '2026-10-01', to: '')).to eq(period)
    end
  end

  it 'keeps the existing maximum span and rejects inverted, malformed and non-scalar inputs' do
    start = Date.new(2026, 1, 1)
    expect(described_class.call(from: start.iso8601, to: (start + 366).iso8601)).to be_a(Range)
    invalid = [{ from: start.iso8601, to: (start + 367).iso8601 }, { from: '2026-10-02', to: '2026-10-01' },
               { from: '2026-02-30' }, { from: ['2026-10-01'] }, { from: '2026-10-01', to: ['2026-10-02'] }]
    invalid.each { |params| expect { described_class.call(params) }.to raise_error(ArgumentError) }
  end
end
