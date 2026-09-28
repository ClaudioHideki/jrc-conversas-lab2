# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'JRC Service Desk CP4 query inputs and arithmetic' do
  it 'normalizes selectors but rejects unknown keys, arrays and loose IDs' do
    expect(JrcServiceDesk::QueryParameters.new({ unit_id: '12', q: ' test ' })['unit_id']).to eq(12)
    [{ unit_id: ['12'] }, { unit_id: '01' }, { account_id: '1' }, { page: 0 }, { per_page: 101 }, { sort: 'random' }].each do |values|
      expect { JrcServiceDesk::QueryParameters.new(values) }.to raise_error(ArgumentError)
    end
  end
  it 'derives all counts from groups and rejects unknown phases or invalid counts' do
    groups = { [1, 'Open fixture', 'open'] => 8, [2, 'Working fixture', 'open'] => 12, [3, 'Done fixture', 'resolved'] => 7 }
    result = JrcServiceDesk::KpiCounts.call(groups)
    expect(result[:total]).to eq(27)
    expect(result[:active]).to eq(20)
    expect(result[:by_status].sum { |v| v[:count] }).to eq(result[:total])
    expect { JrcServiceDesk::KpiCounts.call([1, 'Bad fixture', 'invented'] => 1) }.to raise_error(ArgumentError)
    expect { JrcServiceDesk::KpiCounts.call([1, 'Bad fixture', 'open'] => -1) }.to raise_error(ArgumentError)
  end
end
