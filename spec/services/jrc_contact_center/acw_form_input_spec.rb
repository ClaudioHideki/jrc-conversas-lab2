require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormInput do
  let(:definition) { { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC detail', 'type' => 'text', 'required' => false }] } }
  let(:values) do
    { name: 'SYNTHETIC form', description: 'SYNTHETIC description', status: 'active', definition: definition,
      request_id: SecureRandom.uuid, expected_revision: 0 }
  end
  let(:version) do
    Struct.new(:name, :description, :status, :definition, :revision, keyword_init: true).new(
      **values.slice(:name, :description, :status, :definition), revision: 1
    )
  end

  [{ name: nil }, { name: false }, { name: ' ' }, { name: 'x' * 161 }, { description: nil }, { description: 'x' * 1001 },
   { status: 'published' }, { status: false }, { request_id: nil }, { request_id: 'not-an-identity' },
   { expected_revision: nil }, { expected_revision: '1' }, { expected_revision: -1 }, { expected_revision: 1.0 },
   { expected_revision: 2_147_483_647 }, { name: "SYNTHETIC\0private" }, { description: "SYNTHETIC\0private" }].each_with_index do |invalid, index|
    it "rejects invalid form metadata #{index + 1}:#{invalid.keys.first}:#{invalid.values.first.class}" do
      expect { described_class.new(**values, **invalid) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_revision')
    end
  end

  it 'normalizes the display name and UUID without coercing revision or content' do
    values[:name] = '  SYNTHETIC form  '
    values[:request_id] = values[:request_id].upcase
    input = described_class.new(**values)
    expect(input.name).to eq('SYNTHETIC form')
    expect(input.request_id).to eq(values[:request_id].downcase)
    expect(input.description).to eq(values[:description])
    expect(input.attributes.keys).to contain_exactly(:name, :description, :status, :definition, :request_id)
  end

  it 'copies the validated definition so a subsequent caller edit does not rewrite the candidate revision' do
    input = described_class.new(**values)
    definition['fields'].first['required'] = true
    expect(input.definition['fields'].first['required']).to be(false)
  end

  it 'accepts the exact bounded last precondition and the archived status without inventing lifecycle permission' do
    input = described_class.new(**values, expected_revision: 2_147_483_646, status: 'archived')
    expect(input.expected_revision).to eq(2_147_483_646)
    expect(input.status).to eq('archived')
  end

  it 'matches only the exact content and next revision for later idempotency checks' do
    expect(described_class.new(**values).matches?(version)).to be(true)
    version.revision = 2
    expect(described_class.new(**values).matches?(version)).to be(false)
  end

  %i[name description status definition].each do |field|
    it "does not match a previous receipt when #{field} changed" do
      version[field] = field == :definition ? { 'fields' => [] } : 'SYNTHETIC changed'
      expect(described_class.new(**values).matches?(version)).to be(false)
    end
  end

  it 'validates the full native field contract before exposing candidate attributes' do
    values[:definition]['fields'].first['type'] = 'provider_command'
    expect { described_class.new(**values) }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'rejects authority-looking unknown keys instead of accepting them through the keyword envelope' do
    expect { described_class.new(**values, account_id: 99) }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_revision')
  end
end
