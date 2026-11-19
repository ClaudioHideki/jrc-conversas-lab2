require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormDefinition do
  let(:fields) do
    [
      { 'key' => 'detail', 'label' => 'SYNTHETIC detail', 'type' => 'text', 'required' => true },
      { 'key' => 'count', 'label' => 'SYNTHETIC count', 'type' => 'integer', 'required' => false },
      { 'key' => 'confirmed', 'label' => 'SYNTHETIC confirmation', 'type' => 'boolean', 'required' => true },
      { 'key' => 'result', 'label' => 'SYNTHETIC choice', 'type' => 'select', 'required' => true, 'options' => %w[first second] }
    ]
  end
  let(:definition) { { 'fields' => fields } }

  it 'reuses the native four field types without retrieving any Service Desk records or context' do
    expect(described_class.new(definition).call).to eq(definition)
    expect(fields.pluck('type')).to eq(%w[text integer boolean select])
  end

  it 'returns an independent value so editing a new form version cannot mutate the original definition' do
    result = described_class.new(definition).call
    result['fields'].first['label'] = 'SYNTHETIC next revision'
    expect(definition['fields'].first['label']).to eq('SYNTHETIC detail')
  end

  [nil, [], 'not-an-object', {}, { 'fields' => [] }, { 'fields' => [], 'account_id' => 1 }].each do |input|
    it "rejects an incomplete or unknown definition envelope #{input.inspect}" do
      expect { described_class.new(input).call }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
      end
    end
  end

  it 'rejects whitespace-only labels with a nonprivate field location' do
    fields.first['label'] = '   '
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
      expect(error.fields).to eq(['fields.0.label'])
    end
  end

  ['__proto__', 'constructor', 'prototype'].each do |key|
    it "preserves the native reserved-key rejection for #{key}" do
      fields.first['key'] = key
      expect { described_class.new(definition).call }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
      end
    end
  end

  it 'rejects duplicate keys instead of allowing one answer to satisfy two questions' do
    fields.last['key'] = fields.first['key']
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'does not accept request scope or unknown executable properties as field-definition data' do
    fields.first['unit_id'] = 1
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'rejects unsupported field types without silently turning them into unrestricted text' do
    fields.first['type'] = 'html'
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'requires actual booleans for required flags' do
    fields.first['required'] = 'false'
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'does not retain a hidden options payload on a field that is not a selection' do
    fields.first['options'] = { 'unexpected' => 'value' }
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
      expect(error.fields).to eq(['fields.0.options'])
    end
  end

  { duplicate: ['first', 'first'], blank: ['first', ' '], excessive: Array.new(101) { |i| "option-#{i}" } }.each do |kind, options|
    it "rejects #{kind} choice options" do
      fields.last['options'] = options
      expect { described_class.new(definition).call }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
        expect(error.fields).to eq(['fields.3.options'])
      end
    end
  end

  it 'preserves the native maximum of fifty fields' do
    definition['fields'] = Array.new(51) { |i| fields.first.merge('key' => "field-#{i}") }
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'bounds the complete schema before persisting or emitting a large version snapshot' do
    definition['fields'] = Array.new(50) do |i|
      fields.last.merge('key' => "field-#{i}", 'options' => Array.new(100) { |j| "#{j}-#{'x' * 250}" })
    end
    expect(definition.to_json.bytesize).to be > described_class::MAX_BYTES
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'rejects NUL in a schema label before native JSONB persistence' do
    fields.first['label'] = "SYNTHETIC\0private"
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
      expect(error.message).to eq('invalid_acw_form_definition')
    end
  end

  it 'rejects NUL in a configured selection value before native JSONB persistence' do
    fields.last['options'] = ["SYNTHETIC\0private"]
    expect { described_class.new(definition).call }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
      expect(error.message).to eq('invalid_acw_form_definition')
    end
  end
end
