require 'rails_helper'

RSpec.describe JrcContactCenter::AudioArchiveInput do
  include_context 'with an institutional audio receipt'

  let(:input) { described_class.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context)) }
  let(:selection) do
    [{ audio_asset_id: '9223372036854775806', audio_version_id: '9223372036854775807', inspection_id: '10', sha256: 'a' * 64 }]
  end

  it 'preserves exact bigint identifiers as immutable strings without granting record authority' do
    result = input.call(selection)
    expect(result).to eq([selection.first.stringify_keys])
    expect(result).to be_frozen
    expect(result.first).to be_frozen
    expect(result.first.values).to all(be_frozen)
  end

  it 'rejects coerced, overflowed and malformed native identifiers without truncation' do
    [false, {}, 1.5, '0', '-1', '01', '9223372036854775808', '1/2'].each do |value|
      invalid = selection.first.merge(audio_asset_id: value)
      expect { input.call([invalid]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio')
    end
  end

  it 'requires exact item keys and a lowercase hexadecimal source digest' do
    invalid = [selection.first.except(:inspection_id), selection.first.merge(extra: true),
               selection.first.merge(sha256: false), selection.first.merge(sha256: 'A' * 64)]
    invalid.each do |row|
      expect { input.call([row]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_archive')
    end
  end

  it 'rejects duplicate identities even when one caller supplies integer IDs' do
    row = { audio_asset_id: '1', audio_version_id: '2', inspection_id: '3', sha256: 'a' * 64 }
    duplicate = row.merge(audio_asset_id: 1, audio_version_id: 2)
    expect { input.call([row, duplicate]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_archive')
  end

  it 'does not mutate caller selections while normalizing ActionController parameters' do
    original = selection.deep_dup
    result = input.call([ActionController::Parameters.new(selection.first)])
    expect(result.first.fetch('audio_asset_id')).to eq('9223372036854775806')
    expect(selection).to eq(original)
    expect(selection.first).not_to be_frozen
  end

  it 'advertises a bound no greater than the existing private single-file reader limit' do
    expect(described_class.limits).to eq(max_entries: 20, max_bytes: [40.megabytes, JrcContactCenter::AudioFileInput.max_bytes].min)
  end
end
