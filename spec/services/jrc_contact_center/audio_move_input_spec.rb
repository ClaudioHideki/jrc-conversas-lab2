require 'rails_helper'

RSpec.describe JrcContactCenter::AudioMoveInput do
  include_context 'with an institutional audio receipt'

  let(:input) { described_class.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context)) }
  let(:row) { { 'audio_asset_id' => '9223372036854775807', 'expected_revision' => 'a' * 64 } }

  it 'keeps exact bigint identifiers and freezes normalized descriptors' do
    source = row
    result = input.call([source])
    source['expected_revision'].replace('b' * 64)
    expect(result.first).to eq('audio_asset_id' => '9223372036854775807', 'expected_revision' => 'a' * 64)
    expect([result, result.first, result.first.fetch('audio_asset_id'), result.first.fetch('expected_revision')]).to all(be_frozen)
  end

  it 'rejects malformed or unbounded selections before a write can begin' do
    [nil, false, {}, [], Array.new(21, row)].each do |value|
      expect { input.call(value) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_move')
    end
  end

  it 'rejects duplicate integer and string representations of the same asset' do
    value = row.merge('audio_asset_id' => '12')
    expect { input.call([value, value.merge('audio_asset_id' => 12)]) }
      .to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_move')
  end

  it 'rejects caller authority fields and missing revision keys' do
    [row.merge('unit_id' => '12'), row.merge('user_id' => '12'), row.except('expected_revision')].each do |value|
      expect { input.call([value]) }.to raise_error(JrcContactCenter::OperationError, 'invalid_institutional_audio_move')
    end
  end

  it 'normalizes native request parameters while preserving the native missing revision semantics' do
    value = ActionController::Parameters.new('audio_asset_id' => '12', 'expected_revision' => nil)
    expect(input.call([value])).to eq([{ 'audio_asset_id' => '12', 'expected_revision' => nil }])
  end
end
