require 'rails_helper'

RSpec.describe JrcContactCenter::IvrDraftInput do
  let(:definition) { { 'schema_version' => 1, 'start' => 'end', 'nodes' => [{ 'id' => 'end', 'type' => 'end' }] } }
  let(:values) { { name: 'SYNTHETIC draft', status: 'draft', definition: definition, request_id: SecureRandom.uuid, expected_revision: 0 } }

  [{ name: nil }, { name: false }, { name: ' ' }, { name: 'x' * 161 }, { status: 'published' }, { status: false },
   { request_id: nil }, { request_id: 'not-an-identity' }, { expected_revision: nil }, { expected_revision: '1' },
   { expected_revision: -1 }, { expected_revision: 1.0 }].each do |invalid|
    it "rejects invalid local revision metadata #{invalid.inspect}" do
      expect { described_class.new(**values.merge(invalid)) }.to raise_error(JrcContactCenter::OperationError, 'invalid_ivr_revision')
    end
  end

  it 'does not let a caller mutate a definition after input validation' do
    input = described_class.new(**values)
    definition['nodes'][0]['type'] = 'provider_command'
    expect(input.definition['nodes'][0]['type']).to eq('end')
  end

  it 'normalizes whitespace and UUID casing without inventing operational values' do
    values[:name] = '  SYNTHETIC draft  '
    values[:request_id] = values[:request_id].upcase
    input = described_class.new(**values)
    expect(input.name).to eq('SYNTHETIC draft')
    expect(input.request_id).to eq(values[:request_id].downcase)
    expect(input.definition).to eq(definition)
  end
end
