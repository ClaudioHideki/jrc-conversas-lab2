require 'rails_helper'

RSpec.describe JrcBroker::HistorySyncContract do
  it 'matches the cross-language canonical digest including HTML characters, emoji and Unicode line separators' do
    fixture = JSON.parse(File.read(Rails.root.join('spec/fixtures/jrc_broker/history-canonical-v2.json')))
    service = JrcBroker::HistorySyncV2.allocate
    expect(service.send(:request_hash, fixture.fetch('value'))).to eq(fixture.fetch('sha256'))
  end
end
