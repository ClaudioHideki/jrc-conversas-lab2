# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Real lifecycle transitions feed the SQL dashboard', type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  it 'preserves total=27 and changes phase/active counts after an actual authorized resolve' do
    lc_publish
    rows = 27.times.map { sd_ticket }
    # Fixture setup labels 12 working and resolves 7 through the actual command.
    rows[8, 12].each { |ticket| lc_execute(ticket, 'work_status') }
    rows[20, 7].each { |ticket| lc_execute(ticket, 'resolve') }
    service = JrcServiceDesk::DashboardService.new(user_context: sd_context)
    before = service.call
    expect(before[:total]).to eq(27)
    expect(before[:phases]).to eq('open' => 20, 'waiting' => 0, 'resolved' => 7, 'closed' => 0, 'cancelled' => 0)
    expect(before[:active]).to eq(20)
    expect(before[:by_status].to_h { |r| [r[:id], r[:count]] }).to eq(
      lc_statuses[:open].id.to_s => 8, lc_statuses[:working].id.to_s => 12, lc_statuses[:resolved].id.to_s => 7)
    lc_execute(rows.first, 'resolve')
    after = service.call
    expect(after[:total]).to eq(27)
    expect(after[:phases]['open']).to eq(19)
    expect(after[:phases]['resolved']).to eq(8)
    expect(after[:active]).to eq(19)
    expect(after[:by_status].to_h { |r| [r[:id], r[:count]] }).to eq(
      lc_statuses[:open].id.to_s => 7, lc_statuses[:working].id.to_s => 12, lc_statuses[:resolved].id.to_s => 8)
    expect(after[:total]).to eq(after[:phases].values.sum)
    lc_execute(rows.first, 'reopen')
    expect(service.call[:active]).to eq(20)
  end
end
