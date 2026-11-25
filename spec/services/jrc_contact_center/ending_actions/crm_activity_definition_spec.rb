require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::CrmActivityDefinition do
  let(:parameters) { { 'activity_type' => 'call', 'title' => 'SYNTHETIC confirmed contact', 'description' => 'SYNTHETIC configured result' } }

  def rejection_codes(inputs)
    inputs.map do |input|
      described_class.new.call(input)
    rescue JrcContactCenter::OperationError => e
      e.code
    end
  end

  it 'preserves the explicit native activity type and recorded content without adding identities' do
    result = described_class.new.call(parameters)
    expect(result).to eq(parameters)
    expect(result).not_to equal(parameters)
    minimal = parameters.except('description')
    expect(described_class.new.call(minimal)).to eq(minimal)
    expect(described_class.new.call(parameters.merge('description' => nil))['description']).to be_nil
  end

  it 'normalizes symbol keys without modifying the original parameters' do
    input = parameters.deep_symbolize_keys
    expect(described_class.new.call(input)).to eq(parameters)
    expect(input.keys).to all(be_a(Symbol))
  end

  it 'rejects an unknown activity type instead of silently selecting one' do
    expect { described_class.new.call(parameters.merge('activity_type' => 'unregistered')) }.to raise_error do |error|
      expect(error.code).to eq('invalid_ending_crm_activity_parameters')
    end
  end

  it 'rejects missing fields instead of fabricating the result or title' do
    inputs = %w[activity_type title].map { |key| parameters.except(key) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_crm_activity_parameters'))
  end

  it 'rejects caller identities, commercial changes, and result-state overrides' do
    keys = %w[account_id user_id contact_id company_id business_unit_id lead_id deal_id status completed_at due_at metadata]
    inputs = keys.map { |key| parameters.merge(key => 1) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_crm_activity_parameters'))
  end

  it 'rejects empty text and leading or trailing whitespace' do
    inputs = ['', ' ', ' leading', 'trailing '].map { |value| parameters.merge('title' => value) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_crm_activity_parameters'))
  end

  it 'rejects oversized text and embedded nulls' do
    inputs = ['x' * 6001, "SYNTHETIC\u0000private"].map { |value| parameters.merge('description' => value) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_crm_activity_parameters'))
  end

  it 'rejects nonstring fields without coercion' do
    inputs = parameters.keys.map { |key| parameters.merge(key => false) }
    expect(rejection_codes(inputs)).to all(eq('invalid_ending_crm_activity_parameters'))
  end

  it 'rejects malformed containers instead of accepting an empty action' do
    expect(rejection_codes([nil, false, [], 'call'])).to all(eq('invalid_ending_crm_activity_parameters'))
  end
end
