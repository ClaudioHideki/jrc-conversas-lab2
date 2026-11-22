require 'rails_helper'

RSpec.describe JrcContactCenter::PauseReasonDefinition do
  let(:account) { create(:account) }
  let(:definition) { described_class.new(account: account) }
  let(:legacy) do
    { 'code' => 'synthetic_review', 'name' => 'SYNTHETIC approval reason', 'category' => 'SYNTHETIC', 'description' => '',
      'active' => true, 'minimum_minutes' => nil, 'default_minutes' => 30, 'maximum_minutes' => nil,
      'unit_ids' => [], 'custom_role_ids' => [] }
  end

  it 'preserves an absent approval flag and the exact canonical legacy content without silently activating approval' do
    result = definition.call(legacy)
    expect(result).to eq(legacy)
    expect(result).not_to have_key('approval_required')
    expect(JrcApprovals::Ledger.digest(result)).to eq(JrcApprovals::Ledger.digest(legacy))
    expect(legacy).not_to have_key('approval_required')
  end

  [true, false].each do |required|
    it "preserves an explicit approval boolean #{required.inspect} without adding an approver or policy" do
      value = legacy.merge('approval_required' => required)
      expect(definition.call(value)).to eq(value)
      expect(JrcApprovals::Policy.where(account: account)).to be_empty
      expect(JrcApprovals::Request.where(account: account)).to be_empty
    end
  end

  [nil, 'true', 'false', 0, 1, [], {}].each do |invalid|
    it "rejects malformed approval flag #{invalid.inspect} instead of treating it as disabled or granting a bypass" do
      expect do
        definition.call(legacy.merge('approval_required' => invalid))
      end.to raise_error(described_class::Invalid) { |failure| expect(failure.fields).to eq(['approval_required']) }
    end
  end

  it 'preserves the previous justification flag and its independent strict validation' do
    expect(definition.call(legacy.merge('justification_required' => true)).fetch('justification_required')).to be(true)
    expect do
      definition.call(legacy.merge('justification_required' => 'false'))
    end.to raise_error(described_class::Invalid) { |failure| expect(failure.fields).to eq(['justification_required']) }
  end
end
