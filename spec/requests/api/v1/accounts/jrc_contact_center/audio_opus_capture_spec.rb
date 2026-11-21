require 'rails_helper'

RSpec.describe 'Institutional Opus capture passes the real private admission boundary', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }
  let(:pcm) do
    "RIFF#{[4_036].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[4_000].pack('V')}#{"\0" * 4_000}".b
  end
  let(:encoded) do
    Tempfile.create('jrc-synthetic-opus-source') do |file|
      file.binmode
      file.write(pcm)
      file.flush
      arguments = ['/usr/bin/ffmpeg', '-nostdin', '-v', 'error', '-threads', '1', '-i', 'fd:', '-map', '0:a:0',
                   '-c:a', 'libopus', '-ar', '48000', '-threads', '1', '-f', 'ogg', 'pipe:1']
      result = JrcContactCenter::AudioProbeProcess.new.call(arguments: arguments, file: file)
      raise 'Synthetic native Opus encoding failed' unless result.state == :ok

      result.output
    end
  end
  let(:payload) { encoded }
  let(:multipart_file) { Rack::Test::UploadedFile.new(StringIO.new(payload), 'application/pdf', original_filename: 'SYNTHETIC.ogg') }

  after { multipart_file.close }

  it 'recognizes byte-detected audio/opus and stores canonical OGG only after actual scanning and decoding' do
    expect(Marcel::MimeType.for(StringIO.new(encoded))).to eq('audio/opus')
    post base, headers: headers, params: { asset: { name: 'SYNTHETIC actual Opus' }, unit_id: unit.id, file: multipart_file,
                                           idempotency_key: key, source_kind: 'browser_capture' }
    expect(response).to have_http_status(:created)
    version = JrcContactCenter::AudioVersion.find(response.parsed_body.fetch('received_version').fetch('id'))
    expect(version).to have_attributes(source_kind: 'browser_capture', content_type: 'audio/ogg', sha256: Digest::SHA256.hexdigest(encoded))
    expect(version.inspections.sole.ready?).to be(true)
    expect(version.inspections.sole.metadata).to include('codec' => 'opus', 'content_type' => 'audio/ogg')
    expect(version.blob.download).to eq(encoded)
  end

  context 'when recognizable Opus headers have no decodable audio frames' do
    let(:payload) { encoded.byteslice(0, 47) }

    it 'still rejects the file and leaves no asset, version, observation or owned staging blob' do
      original = [JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count,
                  JrcContactCenter::AudioInspection.count, ActiveStorage::Blob.count]
      post base, headers: headers, params: { asset: { name: 'SYNTHETIC truncated Opus' }, unit_id: unit.id, file: multipart_file,
                                             idempotency_key: key, source_kind: 'browser_capture' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'institutional_audio_invalid_codec')
      expect([JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count,
              JrcContactCenter::AudioInspection.count, ActiveStorage::Blob.count]).to eq(original)
    end
  end
end
