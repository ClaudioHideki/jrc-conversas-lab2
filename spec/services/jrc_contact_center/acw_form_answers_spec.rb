require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormAnswers do
  let(:fields) do
    [
      { 'key' => 'detail', 'label' => 'SYNTHETIC detail', 'type' => 'text', 'required' => true },
      { 'key' => 'count', 'label' => 'SYNTHETIC count', 'type' => 'integer', 'required' => true },
      { 'key' => 'confirmed', 'label' => 'SYNTHETIC confirmation', 'type' => 'boolean', 'required' => true },
      { 'key' => 'result', 'label' => 'SYNTHETIC choice', 'type' => 'select', 'required' => true, 'options' => %w[first second] }
    ]
  end
  let(:definition) { { 'fields' => fields } }
  let(:answers) { { 'detail' => 'SYNTHETIC private note', 'count' => 0, 'confirmed' => false, 'result' => 'first' } }

  it 'accepts explicit false and zero as required answers instead of treating them as missing' do
    expect(described_class.new(definition: definition, answers: answers).call(complete: true)).to eq(answers)
  end

  it 'returns independent data without rewriting private text or selection values' do
    answers['detail'] = '  SYNTHETIC private text <not-rendered-html>  '
    result = described_class.new(definition: definition, answers: answers).call(complete: true)
    expect(result).to eq(answers)
    result['detail'] = 'SYNTHETIC changed by caller'
    expect(answers['detail']).to eq('  SYNTHETIC private text <not-rendered-html>  ')
  end

  it 'allows an incomplete draft without changing required flags in the immutable definition' do
    expect(described_class.new(definition: definition, answers: {}).call(complete: false)).to eq({})
    expect(fields.pluck('required')).to eq([true, true, true, true])
  end

  it 'preserves a partial typed draft, including explicitly unset optional values' do
    partial = { 'detail' => ' ', 'count' => 0, 'confirmed' => false, 'result' => nil }
    expect(described_class.new(definition: definition, answers: partial).call(complete: false)).to eq(partial)
  end

  [nil, [], 'SYNTHETIC', false].each do |value|
    it "rejects a nonobject answers document #{value.inspect}" do
      expect { described_class.new(definition: definition, answers: value).call(complete: false) }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
        expect(error.message).to eq('invalid_acw_form_answers')
      end
    end
  end

  %w[detail count confirmed result].each do |key|
    it "rejects completion when required #{key} is absent" do
      answers.delete(key)
      expect { described_class.new(definition: definition, answers: answers).call(complete: true) }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
      end
    end
  end

  [nil, '', '   '].each do |value|
    it "rejects completion with blank required text #{value.inspect}" do
      answers['detail'] = value
      expect { described_class.new(definition: definition, answers: answers).call(complete: true) }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
      end
    end
  end

  { text_object: ['detail', {}], long_text: ['detail', 'x' * 4001], float: ['count', 1.5],
    unsafe_integer: ['count', 2**53], boolean_string: %w[confirmed false], unknown_option: %w[result not-an-option] }.each do |kind, pair|
    it "preserves the native #{kind} rejection even in drafts" do
      answers[pair.first] = pair.last
      expect { described_class.new(definition: definition, answers: answers).call(complete: false) }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
        expect(error.message).to eq('invalid_acw_form_answers')
      end
    end
  end

  %w[account_id unit_id __proto__ constructor].each do |key|
    it "rejects unknown or authority-looking answer key #{key}" do
      answers[key] = 'SYNTHETIC private value'
      expect { described_class.new(definition: definition, answers: answers).call(complete: false) }.to raise_error do |error|
        expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
        expect(error.message).not_to include('SYNTHETIC private value')
      end
    end
  end

  it 'bounds the full serialized answer envelope including multibyte private text' do
    definition['fields'] = Array.new(50) { |i| fields.first.merge('key' => "field-#{i}") }
    payload = definition['fields'].to_h { |field| [field['key'], 'á' * 4000] }
    expect(payload.to_json.bytesize).to be > described_class::MAX_BYTES
    expect { described_class.new(definition: definition, answers: payload).call(complete: false) }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
    end
  end

  it 'does not coerce an untrusted completion mode into successful required-field validation' do
    expect { described_class.new(definition: definition, answers: {}).call(complete: 'false') }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
    end
  end

  it 'requires the immutable definition contract before evaluating answers' do
    expect { described_class.new(definition: { 'fields' => [] }, answers: answers) }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormDefinition::Invalid')
    end
  end

  it 'rejects NUL in private answers without adding any submitted value to the error' do
    answers['detail'] = "SYNTHETIC\0private"
    expect { described_class.new(definition: definition, answers: answers).call(complete: false) }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::AcwFormAnswers::Invalid')
      expect(error.message).to eq('invalid_acw_form_answers')
    end
  end
end
