require 'minitest/autorun'
module JrcRelationship; end
require_relative '../../app/services/jrc_relationship/sentiment_metric'
class SentimentMetricTest < Minitest::Test
  def test_uses_existing_analyzed_messages_and_returns_evidence_ids
    result = JrcRelationship::SentimentMetric.call([[10, { 'label' => 'positive' }], [11, { 'sentimento_cliente' => 'critico' }]])
    assert_equal 50, result[:normalized]
    assert_equal [10, 11], result[:source_ids]
    assert_equal 'critico', result[:raw][1][:label]
  end
  def test_missing_unknown_or_invalid_analysis_remains_unavailable
    [[], [[1, {}]], [[1, { 'label' => 'nao_identificado' }]], [[1, nil]], [[1, 'negative']]].each do |rows|
      result = JrcRelationship::SentimentMetric.call(rows)
      assert_nil result[:normalized]
      assert_empty result[:source_ids]
    end
  end
end
