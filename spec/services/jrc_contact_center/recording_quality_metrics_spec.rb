# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::RecordingQualityMetrics do
  let(:rows) do
    { 'a' => { 'sentimento_cliente' => 'positivo', 'nota_final' => 0, 'analise_criada_em' => '2026-11-27T10:00:00Z' },
      'b' => { 'sentimento_cliente' => 'negativo', 'nota_final' => 80, 'analise_criada_em' => '2026-11-27T11:00:00Z' },
      'c' => { 'sentimento_cliente' => nil, 'nota_final' => nil, 'analise_criada_em' => '2026-11-27T12:00:00Z' } }
  end
  let(:metrics) { described_class.new(rows: rows, call_ids: %w[a b c d]) }

  it 'states the whole original-analysis denominator without counting an absent analysis as a neutral or positive result' do
    expect(metrics.summary).to include(universe: 4, analyzed: 3, without_analysis: 1, unclassified: 1,
                                       counts: { 'positivo' => 1, 'neutro' => 0, 'negativo' => 1 },
                                       percentages: { 'positivo' => 33.33, 'neutro' => 0.0, 'negativo' => 33.33 },
                                       denominator: 'latest_original_analyses')
  end

  it 'preserves a real zero quality score and keeps its average distinct from sentiment' do
    expect(metrics.summary).to include(quality_measured: 2, quality_average: 40.0)
    expect(metrics.present('a')).to include(available: true, sentiment: 'positivo', quality_score: 0)
    expect(metrics.present('b')).to include(available: true, sentiment: 'negativo', quality_score: 80)
  end

  it 'keeps unknown or missing sentiment separate from records without any analysis' do
    rows['a']['sentimento_cliente'] = 'SYNTHETIC not a known label'
    expect(metrics.summary).to include(unclassified: 2, without_analysis: 1)
    expect(metrics.selected_ids('unclassified')).to eq(%w[a c])
    expect(metrics.selected_ids('without_analysis')).to eq(['d'])
    expect(metrics.present('d')).to eq(available: false, sentiment: nil, quality_score: nil)
  end

  it 'does not change the aggregate denominator when selecting a sentiment segment' do
    before = metrics.summary
    expect(metrics.selected_ids('negativo')).to eq(['b'])
    expect(metrics.summary).to eq(before)
    expect(metrics.selected_ids('')).to eq(%w[a b c d])
  end

  it 'does not invent a percentage or a quality average when no original analyses exist' do
    result = described_class.new(rows: {}, call_ids: %w[a b]).summary
    expect(result).to include(analyzed: 0, without_analysis: 2, quality_measured: 0, quality_average: nil)
    expect(result.fetch(:percentages).values).to eq([nil, nil, nil])
  end

  [nil, '', '90', -1, 101, Float::NAN, Float::INFINITY].each do |value|
    it "does not convert an unavailable or invalid native quality score #{value.inspect} into zero" do
      rows.each_value { |row| row['nota_final'] = value }
      expect(metrics.summary).to include(quality_measured: 0, quality_average: nil)
      expect(metrics.present('a').fetch(:quality_score)).to be_nil
    end
  end

  [%w[positivo negativo], { value: 'positivo' }, 'critical', false].each do |value|
    it "rejects a malformed sentiment selection #{value.inspect}" do
      expect { metrics.selected_ids(value) }.to raise_error(JrcContactCenter::OperationError, 'invalid_recording_filter')
    end
  end
end
