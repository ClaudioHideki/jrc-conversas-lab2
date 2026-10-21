# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::MetricsSummary do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  it 'sums daily facts only from the authorized account scope' do
    JrcContactCenter::DailyFact.create!(account: account, fact_date: Date.current, offered_count: 5, answered_count: 3, talk_seconds: 60)
    JrcContactCenter::DailyFact.create!(account: other_account, fact_date: Date.current, offered_count: 100, answered_count: 100)

    result = described_class.new(scope: JrcContactCenter::DailyFact.where(account: account),
                                 from: Date.current, to: Date.current).call

    expect(result).to include(offered_count: 5, answered_count: 3, talk_seconds: 60)
    expect(result).to include(tme_seconds: nil, tma_seconds: nil, acw_average_seconds: nil, sla: nil)
  end

  it 'does not include unmeasured historical durations in confirmed averages' do
    JrcContactCenter::DailyFact.create!(account: account, fact_date: Date.current, talk_seconds: 1000,
                                        data: { 'talk_measured_count' => 2, 'talk_measured_seconds' => 100 })
    result = described_class.new(scope: JrcContactCenter::DailyFact.where(account: account),
                                 from: Date.current, to: Date.current).call

    expect(result).to include(talk_seconds: 1000, tma_seconds: 50.0)
  end
end
