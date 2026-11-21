require 'rails_helper'

RSpec.describe JrcContactCenter::TeamSupervisionInput do
  let(:values) { { 'primary_account_user_id' => '2', 'additional_account_user_ids' => %w[4 3] } }

  it 'preserves explicit primary and additional roles without generating membership or permission attributes' do
    input = described_class.new(values)
    expect(input.assignments).to eq([{ account_user_id: 2, kind: 'primary' }, { account_user_id: 3, kind: 'additional' },
                                     { account_user_id: 4, kind: 'additional' }])
    expect(input).to be_frozen
    expect(input.additional_ids).to be_frozen
  end

  it 'does not invent a required primary or convert a missing selection into the first additional supervisor' do
    values['primary_account_user_id'] = nil
    input = described_class.new(values)
    expect(input.primary_id).to be_nil
    expect(input.assignments.map { |row| row.fetch(:kind) }).to eq(%w[additional additional])
  end

  it 'accepts an empty explicit selection and exact native bigint IDs without Float conversion' do
    expect(described_class.new('primary_account_user_id' => nil, 'additional_account_user_ids' => []).assignments).to eq([])
    values['primary_account_user_id'] = '9223372036854775807'
    expect(described_class.new(values).primary_id).to eq(9_223_372_036_854_775_807)
  end

  it 'copies the caller selection before freezing, sorting and building operational metadata' do
    input = described_class.new(values)
    values['additional_account_user_ids'] << '8'
    expect(input.additional_ids).to eq([3, 4])
    expect { input.additional_ids << 8 }.to raise_error(FrozenError)
    expect(values['additional_account_user_ids']).to eq(%w[4 3 8])
  end

  [nil, false, [], 'invalid'].each do |value|
    it "rejects malformed body #{value.inspect}" do
      expect { described_class.new(value) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
    end
  end

  %w[account_id unit_id team_id actor_id eligible allowed denied queue_id participates supervises].each do |field|
    it "rejects client authority or operational attributes #{field}" do
      values[field] = true
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
    end
  end

  [nil, false, '3', {}].each do |value|
    it "rejects malformed additional selection #{value.inspect}" do
      values['additional_account_user_ids'] = value
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
    end
  end

  [false, 0, -1, 2.5, '2.5', '2e0', '02', '+2', '2evil', ' 2', '2 ', '9223372036854775808', {}].each do |value|
    it "rejects malformed exact primary ID #{value.inspect}" do
      values['primary_account_user_id'] = value
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
    end
  end

  it 'rejects duplicate additional users or the same person in both roles rather than silently deduplicating' do
    values['additional_account_user_ids'] = ['3', 3]
    expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
    values['additional_account_user_ids'] = ['2']
    expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
  end

  it 'requires both explicit fields and canonical string keys' do
    expect { described_class.new(values.except('primary_account_user_id')) }.to raise_error(JrcContactCenter::OperationError)
    expect { described_class.new(values.symbolize_keys) }.to raise_error(JrcContactCenter::OperationError)
  end

  it 'bounds the selection without truncating or interpreting IDs as grants' do
    values['additional_account_user_ids'] = (3..131).map(&:to_s)
    expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_team_supervision')
    values['additional_account_user_ids'].pop
    expect(described_class.new(values).additional_ids.length).to eq(128)
  end
end
