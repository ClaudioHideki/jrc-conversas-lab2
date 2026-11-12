require 'rails_helper'

RSpec.describe JrcBroker::HistorySyncMedia do
  it 'bounds the physical object stream by the immutable descriptor before accumulating more bytes' do
    media = described_class.new(nil)
    descriptor = { 'byte_size' => 4 }
    blob = double
    consumed_tail = false
    allow(blob).to receive(:download) do |&reader|
      reader.call('1234')
      reader.call('5')
      consumed_tail = true
      reader.call('synthetic unreachable tail')
    end
    expect { media.verify_blob!(blob, descriptor) }.to raise_error(ArgumentError, 'historical_media_integrity')
    expect(consumed_tail).to be(false)
  end

  it 'verifies the complete checksum and MIME after bounded physical reads' do
    bytes = File.binread(Rails.root.join('spec/assets/sample.png'))
    descriptor = { 'filename' => 'synthetic.png', 'mime_type' => 'image/png', 'media_type' => 'IMAGE',
                   'byte_size' => bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(bytes) }
    blob = double
    allow(blob).to receive(:download).and_yield(bytes[0, 7]).and_yield(bytes[7..])
    expect { described_class.new(nil).verify_blob!(blob, descriptor) }.not_to raise_error
  end
end
