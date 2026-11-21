require 'rails_helper'

RSpec.describe JrcContactCenter::QualityReviewInput do
  let(:values) do
    { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC reviewed summary',
      'adjusted_themes' => ['SYNTHETIC service'], 'recommendation_ids' => ['b' * 64],
      'justification' => 'SYNTHETIC explicit human reason', 'expected_revision' => 0,
      'expected_source_sha256' => 'a' * 64, 'request_id' => SecureRandom.uuid }
  end

  it 'keeps the explicit human classification separate from the immutable original analysis' do
    input = described_class.new(values)
    expect(input.attributes).to eq(values)
    expect(input.attributes.keys).not_to include('original_analysis', 'classificacao_ligacao', 'audio', 'transcript')
  end

  it 'takes an immutable private copy without freezing or rewriting the caller values' do
    input = described_class.new(values)
    values['adjusted_themes'].first.replace('SYNTHETIC later edit')
    expect(input.attributes.fetch('adjusted_themes')).to eq(['SYNTHETIC service'])
    expect { input.attributes['classification'] = 'positive' }.to raise_error(FrozenError)
    expect { input.attributes.fetch('adjusted_themes').first.replace('x') }.to raise_error(FrozenError)
    expect { input.attributes.fetch('recommendation_ids') << 'c' * 64 }.to raise_error(FrozenError)
  end

  it 'normalizes explicit input without assigning actor, permissions, origin or an operational action' do
    values.merge!('request_id' => values.fetch('request_id').upcase, 'justification' => '  SYNTHETIC reason  ',
                  'adjusted_themes' => [' SYNTHETIC theme ', 'SYNTHETIC theme'], 'recommendation_ids' => ['c' * 64, 'b' * 64, 'c' * 64])
    input = described_class.new(values)
    expect(input.attributes.fetch('justification')).to eq('SYNTHETIC reason')
    expect(input.attributes.fetch('adjusted_themes')).to eq(['SYNTHETIC theme'])
    expect(input.attributes.fetch('recommendation_ids')).to eq(['b' * 64, 'c' * 64])
    expect(input.attributes.fetch('request_id')).to eq(values.fetch('request_id').downcase)
    expect(values.fetch('justification')).to start_with('  ')
  end

  %w[positive neutral negative].each do |classification|
    it "accepts only the Word's explicit human classification #{classification}" do
      values['classification'] = classification
      expect(described_class.new(values).attributes.fetch('classification')).to eq(classification)
    end
  end

  [nil, false, [], {}, '', 'excellent', 'positive ', 'Positivo'].each do |invalid|
    it "requires a valid human classification rather than silently reinterpreting #{invalid.inspect}" do
      values['classification'] = invalid
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'quality_review_classification_required')
    end
  end

  [nil, false, [], {}, '', " \t\n"].each do |invalid|
    it "requires an explicit human reason #{invalid.inspect}" do
      values['justification'] = invalid
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'quality_review_justification_required')
    end
  end

  %w[account_id unit_id company_id user_id actor_id granted_permissions original_analysis recording_url execute_action].each do |field|
    it "rejects authority, original-data and operational overrides in #{field}" do
      values[field] = 'untrusted'
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
    end
  end

  [nil, false, -1, '0', 0.0, 2_147_483_648].each do |invalid|
    it "does not invent a missing or invalid revision #{invalid.inspect}" do
      values['expected_revision'] = invalid
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
    end
  end

  [nil, false, [], '', 'a' * 63, 'A' * 64, "#{'a' * 64}\n"].each do |invalid|
    it "requires an exact original source hash #{invalid.inspect}" do
      values['expected_source_sha256'] = invalid
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
    end
  end

  it 'requires a caller-provided UUID rather than creating a hidden request identity' do
    values.delete('request_id')
    expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
  end

  it 'allows an explicitly empty adjustment without deleting or manufacturing the original source' do
    values.merge!('adjusted_summary' => '', 'adjusted_themes' => [], 'recommendation_ids' => [])
    input = described_class.new(values)
    expect(input.attributes.fetch('adjusted_summary')).to eq('')
    expect(input.validate_source!(actual_sha256: 'a' * 64, available_recommendation_ids: [])).to be(input)
  end

  it 'accepts only suggestions that remain present in the current server-authorized source' do
    input = described_class.new(values)
    expect(input.validate_source!(actual_sha256: 'a' * 64, available_recommendation_ids: ['b' * 64])).to be(input)
    expect do
      input.validate_source!(actual_sha256: 'a' * 64, available_recommendation_ids: ['c' * 64])
    end.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
  end

  it 'reports changed original evidence as a conflict without rewriting the input or source hash' do
    input = described_class.new(values)
    expect do
      input.validate_source!(actual_sha256: 'c' * 64, available_recommendation_ids: ['b' * 64])
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('quality_review_source_changed') }
    expect(input.attributes.fetch('expected_source_sha256')).to eq('a' * 64)
  end

  [nil, false, {}, ['not-an-original-suggestion'], [nil]].each do |invalid|
    it "rejects an incomplete server suggestion projection #{invalid.inspect}" do
      expect do
        described_class.new(values).validate_source!(actual_sha256: 'a' * 64, available_recommendation_ids: invalid)
      end.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
    end
  end

  { 'adjusted_summary' => 'x' * 48_001, 'justification' => 'x' * 8_001,
    'adjusted_themes' => Array.new(41, 'SYNTHETIC'), 'recommendation_ids' => Array.new(41, 'b' * 64) }.each do |field, invalid|
    it "bounds #{field} without truncation or silently dropping entries" do
      values[field] = invalid
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
    end
  end

  ['adjusted_summary', 'justification'].each do |field|
    it "rejects unsafe control characters in #{field} without logging the content" do
      values[field] = "SYNTHETIC\0payload"
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, 'invalid_quality_review')
    end
  end

  %w[justification adjusted_summary expected_source_sha256 request_id].each do |field|
    it "rejects malformed UTF8 in #{field} as a value error without exposing content" do
      values[field] = "\xFF".dup.force_encoding(Encoding::UTF_8)
      code = field == 'justification' ? 'quality_review_justification_required' : 'invalid_quality_review'
      expect { described_class.new(values) }.to raise_error(JrcContactCenter::OperationError, code)
    end
  end
end
