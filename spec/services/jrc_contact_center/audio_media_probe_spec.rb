require 'rails_helper'

RSpec.describe JrcContactCenter::AudioMediaProbe do
  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && RUBY_PLATFORM.include?('linux')
    raise 'Native media probes require the exclusively owned disposable Linux runner' unless owned
  end

  let(:bytes) do
    "RIFF#{[4_036].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[4_000].pack('V')}#{"\0" * 4_000}".b
  end

  def with_native_media(data)
    Tempfile.create('jrc-synthetic-codec-proof') do |file|
      file.binmode
      file.write(data)
      file.flush
      yield file
    end
  end

  it 'probes and actually decodes a real seekable WAV without inventing duration or releasing private bytes' do
    with_native_media(bytes) do |file|
      result = described_class.new.call(file)
      expect(result.fetch(:state)).to eq('valid')
      expect(result.fetch(:metadata)).to include('duration_ms' => 250, 'sample_rate' => 8_000, 'channels' => 1, 'codec' => 'pcm_s16le')
      expect(result.fetch(:metadata).fetch('probe_version')).to start_with('ffprobe version ')
      expect(result.fetch(:decoder_version)).to start_with('ffmpeg version ')
      expect(file).not_to be_closed
    end
  end

  it 'rejects an empty WAV header instead of mistaking its declared data length for actual playable media' do
    with_native_media(bytes.byteslice(0, 44)) do |file|
      result = described_class.new.call(file)
      expect(result).to eq(state: 'invalid', metadata: {}, decoder_version: nil)
    end
  end

  it 'does not follow a playlist, external media URL or arbitrary protocol as institutional audio' do
    with_native_media("#EXTM3U\n#EXTINF:1,\nhttps://invalid.example/SYNTHETIC.wav\n") do |file|
      expect(described_class.new.call(file)).to eq(state: 'invalid', metadata: {}, decoder_version: nil)
    end
  end

  it 'distinguishes a missing native dependency from an invalid file, without a silent fallback' do
    stub_const('JrcContactCenter::AudioMediaDecoder::BINARY', '/nonexistent/jrc-synthetic-decoder')
    with_native_media(bytes) do |file|
      expect(described_class.new.call(file)).to eq(state: 'unavailable', metadata: {}, decoder_version: nil)
    end
  end

  { 'libmp3lame' => ['mp3', 'audio/mpeg'], 'libvorbis' => ['ogg', 'audio/ogg'], 'aac' => ['mp4', 'audio/mp4'] }.each do |codec, (container, type)|
    it "derives actual #{container} metadata from an owned synthetic encoding, not fixture JSON" do
      with_native_media(bytes) do |file|
        arguments = ['/usr/bin/ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-i', 'fd:', '-map', '0:a:0',
                     '-c:a', codec, '-threads', '1', '-metadata', 'title=SYNTHETIC private media tag']
        arguments += ['-movflags', 'frag_keyframe+empty_moov'] if container == 'mp4'
        encoded = JrcContactCenter::AudioProbeProcess.new.call(arguments: arguments + ['-f', container, 'pipe:1'], file: file)
        expect(encoded.state).to eq(:ok)
        with_native_media(encoded.output) do |media|
          result = described_class.new.call(media)
          expect(result.fetch(:state)).to eq('valid')
          expect(result.fetch(:metadata).fetch('duration_ms')).to be_positive
          expect(result.fetch(:metadata).fetch('content_type')).to eq(type)
          expect(result.to_json).not_to include('private media tag', media.path)
        end
      end
    end
  end
end
