require 'rails_helper'

RSpec.describe JrcContactCenter::IvrGraphSchema, '.validate!' do
  let(:reference) { { 'asset_id' => '1', 'version_id' => '2', 'sha256' => 'a' * 64 } }
  let(:menu) do
    { 'id' => 'entry', 'type' => 'menu', 'timeout_seconds' => 5, 'max_attempts' => 1,
      'options' => [{ 'digit' => '1', 'target' => 'end' }], 'on_timeout' => 'end', 'on_invalid' => 'end' }
  end
  let(:definition) { { 'schema_version' => 2, 'start' => 'entry', 'nodes' => [menu, { 'id' => 'end', 'type' => 'end' }] } }

  it 'keeps the original schema1 unchanged and accepts its existing menu shape' do
    original = definition.merge('schema_version' => 1)
    expect { described_class.validate!(original) }.not_to raise_error
    expect(described_class::MENU.fetch('properties')).not_to have_key('audio_reference')
    expect(described_class::SCHEMA.dig('properties', 'schema_version')).to eq('const' => 1)
  end

  it 'adds only the explicit internal schema2 exact version reference without implying provider support' do
    menu['audio_reference'] = reference
    before = definition.deep_dup
    expect { described_class.validate!(definition) }.not_to raise_error
    expect(definition).to eq(before)
    expect(described_class::SCHEMA.dig('properties', 'nodes', 'items', 'oneOf')).not_to include(described_class::MENU_V2)
  end

  it 'allows a schema2 menu without an audio link after an explicit unlink' do
    expect { described_class.validate!(definition) }.not_to raise_error
  end

  it 'continues rejecting the new field under schema1 rather than silently interpreting old snapshots' do
    definition['schema_version'] = 1
    menu['audio_reference'] = reference
    expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
  end

  [nil, false, [], 'asset:1', {}, { 'asset_id' => '1', 'version_id' => '2' }].each do |invalid|
    it "rejects malformed audio metadata #{invalid.inspect}" do
      menu['audio_reference'] = invalid
      expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end

  invalid_ids = [0, 1, false, [], {}, '0', '-1', '1.0', '1/2', "1\n", '99999999999999999999']
  %w[asset_id version_id].each do |field|
    invalid_ids.each do |invalid|
      it "rejects an untyped or noncanonical #{field} identity #{invalid.inspect}" do
        menu['audio_reference'] = reference.merge(field => invalid)
        expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
      end
    end
  end

  ['', 'a' * 63, 'A' * 64, "#{'a' * 64}\n", false].each do |invalid|
    it "rejects malformed exact hash #{invalid.inspect}" do
      menu['audio_reference'] = reference.merge('sha256' => invalid)
      expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end

  %w[account_id user_id unit_id blob_id provider_command url].each do |field|
    it "rejects scope or provider override #{field}" do
      menu['audio_reference'] = reference.merge(field => 'untrusted')
      expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end

  [3, '2', 2.0, true].each do |invalid|
    it "does not reinterpret unsupported or untyped schema identity #{invalid.inspect}" do
      definition['schema_version'] = invalid
      expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
    end
  end

  it 'does not accept a menu audio property on a terminal node' do
    definition['nodes'].last['audio_reference'] = reference
    expect { described_class.validate!(definition) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_graph')
  end
end
