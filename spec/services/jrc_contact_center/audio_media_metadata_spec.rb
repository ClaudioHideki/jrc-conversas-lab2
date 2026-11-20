require 'rails_helper'

RSpec.describe JrcContactCenter::AudioMediaMetadata do
  let(:version) { 'ffprobe version SYNTHETIC parser fixture, not an external media proof' }
  let(:stream) { { 'codec_type' => 'audio', 'codec_name' => 'pcm_s16le', 'sample_rate' => '8000', 'channels' => 1, 'duration' => '1.250' } }
  let(:document) { { 'streams' => [stream], 'format' => { 'format_name' => 'wav', 'duration' => '1.250' } } }

  it 'extracts only actual whitelisted metadata and converts seconds to milliseconds' do
    document['format']['filename'] = 'SYNTHETIC private storage locator'
    document['format']['tags'] = { 'comment' => 'SYNTHETIC private file tag' }
    metadata = described_class.extract(document, version: version)
    expect(metadata).to include('duration_ms' => 1250, 'sample_rate' => 8000, 'channels' => 1, 'content_type' => 'audio/wav')
    expect(metadata.keys.sort).to eq(described_class::FIELDS.sort)
    expect(metadata.to_json).not_to include('storage locator', 'private file tag')
    expect(described_class.valid?(metadata)).to be(true)
  end

  it 'does not replace missing duration with a guessed zero or default' do
    stream.delete('duration')
    document['format'].delete('duration')
    expect(described_class.extract(document, version: version)).to be_nil
  end

  it 'can use the real container duration when the stream has no duration' do
    stream.delete('duration')
    expect(described_class.extract(document, version: version).fetch('duration_ms')).to eq(1250)
  end

  it 'rejects video, extra streams and unsupported containers' do
    stream['codec_type'] = 'video'
    expect(described_class.extract(document, version: version)).to be_nil
    stream['codec_type'] = 'audio'
    document['streams'] << stream.dup
    expect(described_class.extract(document, version: version)).to be_nil
    document['streams'].pop
    document['format']['format_name'] = 'hls'
    expect(described_class.extract(document, version: version)).to be_nil
  end

  ['NaN', 'Infinity', '-1', '0', '999999999999999999999'].each do |invalid|
    it "does not turn invalid or out-of-range duration #{invalid} into playable metadata" do
      stream['duration'] = invalid
      document['format']['duration'] = invalid
      expect(described_class.extract(document, version: version)).to be_nil
    end
  end

  [nil, [], false, {}, { 'streams' => 'invalid' }, { 'streams' => [nil] }].each do |invalid|
    it "rejects malformed probe document #{invalid.inspect} without producing a fake format" do
      expect(described_class.extract(invalid, version: version)).to be_nil
    end
  end

  it 'does not accept a client-shaped partial metadata document as a ready observation' do
    expect(described_class.valid?({ 'duration_ms' => 1 })).to be(false)
    expect(described_class.valid?({ duration_ms: 1 })).to be(false)
    metadata = described_class.extract(document, version: version)
    metadata['channels'] = '1'
    expect(described_class.valid?(metadata)).to be(false)
  end
end
