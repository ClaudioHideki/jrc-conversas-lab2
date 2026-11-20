require 'rails_helper'
require 'digest'

RSpec.describe JrcContactCenter::AudioMediaDecoder do
  let(:decoder) { described_class.new }

  context 'with synthetic parser results, not native decoding evidence' do
    it 'rejects an empty decoded stream even when the native command would exit successfully' do
      expect(decoder.send(:decoded_frames?, "SHA256=#{Digest::SHA256.hexdigest('')}\n")).to be(false)
      expect(decoder.send(:decoded_frames?, "progress=end\n")).to be(false)
    end

    it 'requires one complete SHA-256 record, never a partial, wrong-algorithm or extra-output result' do
      hash = Digest::SHA256.hexdigest('SYNTHETIC decoded audio')
      invalid = ["SHA256=#{hash}", "SHA256=#{hash}\nEXTRA\n", "MD5=#{hash}\n", "SHA256=invalid\n", '']
      expect(invalid.map { |value| decoder.send(:decoded_frames?, value) }).to eq([false] * invalid.length)
      expect(decoder.send(:decoded_frames?, "SHA256=#{hash}\n")).to be(true)
    end
  end

  context 'with the owned real native decoder and synthetic PCM bytes' do
    let(:pcm) { "\0".b * 4_000 }
    let(:wave) { "RIFF#{[4_036].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[4_000].pack('V')}#{pcm}".b }
    let(:file) do
      temporary = Tempfile.new('SYNTHETIC-pcm-proof')
      temporary.binmode
      temporary.write(wave)
      temporary.flush
      temporary
    end

    before do
      owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
      raise 'Native media proof requires the owned disposable Linux runner' unless owned && RUBY_PLATFORM.include?('linux')
    end

    after { file.close! }

    it 'proves actual decoded PCM independently of progress timestamps and preserves the previous diagnostic' do
      process = JrcContactCenter::AudioProbeProcess.new
      actual = process.call(arguments: decoder.send(:arguments), file: file)
      legacy = process.call(arguments: [described_class::BINARY, '-nostdin', '-v', 'error', '-xerror', '-err_detect', 'explode',
                                        '-max_alloc', '67108864', '-progress', 'pipe:1', '-nostats', '-protocol_whitelist', 'fd',
                                        '-format_whitelist', described_class::FORMATS, '-max_streams', '1', '-threads', '1',
                                        '-i', 'fd:', '-map', '0:a:0', '-threads', '1', '-f', 'null', '-'], file: file)
      probe = JrcContactCenter::AudioMediaProbe.new
      metadata = process.call(arguments: probe.send(:arguments), file: file)
      report = { synthetic: true, expected_decoded_pcm_sha256: Digest::SHA256.hexdigest(pcm),
                 current_state: actual.state, current_output: actual.output, previous_state: legacy.state,
                 previous_progress_output: legacy.output, native_probe_state: metadata.state, native_probe_output: metadata.output }
      File.write('/tmp/call-center-audio-wav-diagnostic.json', JSON.pretty_generate(report))
      expect(actual.state).to eq(:ok)
      expect(actual.output).to eq("SHA256=#{Digest::SHA256.hexdigest(pcm)}\n")
      expect(decoder.call(file)).to eq('valid')
      expect(probe.call(file).fetch(:state)).to eq('valid')
    end

    it 'does not accept a WAV header without decoded PCM merely because the container is recognized' do
      file.truncate(44)
      file.flush
      expect(decoder.call(file)).to eq('invalid')
      expect(JrcContactCenter::AudioMediaProbe.new.call(file).fetch(:state)).to eq('invalid')
    end
  end
end
