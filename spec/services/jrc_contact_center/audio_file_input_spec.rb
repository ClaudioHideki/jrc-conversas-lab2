require 'rails_helper'

RSpec.describe JrcContactCenter::AudioFileInput do
  include_context 'with an institutional audio receipt'

  it 'detects the actual bytes instead of trusting the declared client MIME' do
    upload.content_type = 'application/pdf'
    input = described_class.new(file: upload)
    expect(input.content_type).to eq('audio/wav')
    expect(input.byte_size).to eq(bytes.bytesize)
    expect(input.sha256).to eq(Digest::SHA256.hexdigest(bytes))
  end

  it 'refuses a nonaudio file despite a .wav name and audio MIME claim' do
    upload.tempfile.rewind
    upload.tempfile.truncate(0)
    upload.tempfile.write('%PDF-1.7 SYNTHETIC invalid audio')
    upload.tempfile.rewind
    expect { described_class.new(file: upload) }.to raise_error(JrcContactCenter::OperationError, 'unsupported_institutional_audio_file')
  end

  it 'refuses an empty actual upload' do
    upload.tempfile.truncate(0)
    expect { described_class.new(file: upload) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_file')
  end

  it 'enforces the existing global size boundary without allocating an oversized file' do
    allow(described_class).to receive(:max_bytes).and_return(bytes.bytesize - 1)
    expect { described_class.new(file: upload) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_file')
  end

  [nil, {}, 'signed-storage-locator', false].each do |invalid|
    it "refuses a non-upload #{invalid.class} instead of treating a locator as authorized bytes" do
      expect { described_class.new(file: invalid) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_file')
    end
  end

  it 'rejects actual stored-byte corruption and compensates only that uncommitted private upload' do
    input = described_class.new(file: upload)
    blob = JrcContactCenter::PrivateAudioBlob.upload(file: upload, filename: input.filename, content_type: input.content_type)
    blob.service.upload(blob.key, StringIO.new('SYNTHETIC corrupt bytes'))
    expect { input.verify_stored!(blob) }.to raise_error(ActiveStorage::IntegrityError)
    JrcContactCenter::PrivateAudioBlob.clean_uncommitted(blob)
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  it 'independently rejects another same-size WAV with its own valid native checksum but a different exact SHA-256' do
    input = described_class.new(file: upload)
    changed = bytes.dup
    changed.setbyte(changed.bytesize - 1, 1)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(changed), filename: 'SYNTHETIC.wav', content_type: 'audio/wav', identify: false)
    expect(blob.byte_size).to eq(input.byte_size)
    expect { input.verify_stored!(blob) }.to raise_error(ActiveStorage::IntegrityError)
    blob.purge
    expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
  end

  context 'with an Opus identification header, not yet evidence of playable media' do
    let(:bytes) do
      header = 'OggS'.b + ("\0".b * 24)
      header.setbyte(5, 2)
      header.setbyte(26, 1)
      header.setbyte(27, 19)
      header + 'OpusHead'.b + [1, 1, 312, 48_000, 0, 0].pack('CCvVs<C')
    end

    it 'reproduces the former rejection when the byte-detected Opus subtype has no canonical mapping' do
      expect(Marcel::MimeType.for(upload.tempfile)).to eq('audio/opus')
      stub_const('JrcContactCenter::AudioFileInput::TYPES', described_class::TYPES.except('audio/opus'))
      expect { described_class.new(file: upload) }.to raise_error(JrcContactCenter::OperationError, 'unsupported_institutional_audio_file')
    end

    it 'normalizes the actual Opus container without trusting a filename or client MIME and without rewriting bytes' do
      upload.content_type = 'application/pdf'
      input = described_class.new(file: upload)
      expect(Marcel::MimeType.for(upload.tempfile)).to eq('audio/opus')
      expect(input.content_type).to eq('audio/ogg')
      expect(input.sha256).to eq(Digest::SHA256.hexdigest(bytes))
      expect(File.binread(upload.tempfile.path)).to eq(bytes)
    end
  end
end
