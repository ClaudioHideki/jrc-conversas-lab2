require 'rails_helper'

RSpec.describe JrcBroker::HistoryMediaBodyLimit do
  let(:app) { ->(_env) { [200, {}, ['synthetic']] } }
  let(:guard) { described_class.new(app) }
  let(:path) { '/api/v1/accounts/1/jrc_history_sync/v2/inboxes/1/media' }

  it 'bounds chunked input before multipart parsing and never invokes the application for an oversized body' do
    input = StringIO.new('x' * (described_class::LIMIT + 1))
    expect(app).not_to receive(:call)
    expect(guard.call('PATH_INFO' => path, 'REQUEST_METHOD' => 'POST', 'rack.input' => input).first).to eq(413)
  end

  it 'rejects a truncated declared length and preserves unrelated routes' do
    expect(guard.call('PATH_INFO' => path, 'REQUEST_METHOD' => 'POST', 'CONTENT_LENGTH' => '20',
                      'rack.input' => StringIO.new('short')).first).to eq(400)
    expect(guard.call('PATH_INFO' => '/unrelated', 'REQUEST_METHOD' => 'POST').first).to eq(200)
  end

  ['/media.json', '/media/', '/media.json/'].each do |suffix|
    it "bounds the Rails alternate route #{suffix} before parsing the multipart body" do
      alternate = path.delete_suffix('/media') + suffix
      expect(app).not_to receive(:call)
      expect(guard.call('PATH_INFO' => alternate, 'REQUEST_METHOD' => 'POST', 'CONTENT_LENGTH' => (described_class::LIMIT + 1).to_s).first).to eq(413)
    end
  end
end
