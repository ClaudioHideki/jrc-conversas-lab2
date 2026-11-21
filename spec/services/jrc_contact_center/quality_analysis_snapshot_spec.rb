require 'rails_helper'

RSpec.describe JrcContactCenter::QualityAnalysisSnapshot do
  let(:analysis) do
    { id: 'SYNTHETIC-analysis-1', chamada_id: 'SYNTHETIC-source-call-1', call_id: 'SYNTHETIC-provider-call-1',
      classificacao_ligacao: 'excelente', sentimento_cliente: 'positivo', nota_final: 0,
      resumo_conversa: 'SYNTHETIC original summary', confianca_transcricao: nil,
      texto_transcrito: 'SYNTHETIC original transcript', created_at: '2026-11-21T00:00:00Z',
      payload_completo: { 'assuntos_abordados' => ['SYNTHETIC service'],
                          'oportunidades_melhoria' => ['SYNTHETIC optional suggestion'], 'treinamento_recomendado' => [] } }
  end

  def capture(values = analysis, call_id: 'SYNTHETIC-provider-call-1')
    described_class.new(analysis: values, authorized_call_id: call_id)
  end

  it 'keeps actual quality, sentiment, zero score, missing confidence and original transcript distinct' do
    snapshot = capture
    expect(snapshot.data).to include('classificacao_ligacao' => 'excelente', 'sentimento_cliente' => 'positivo', 'nota_final' => 0)
    expect(snapshot.data.fetch('confianca_transcricao')).to be_nil
    expect(snapshot.data.fetch('texto_transcrito')).to eq('SYNTHETIC original transcript')
    expect(snapshot.data.fetch('payload_completo')).not_to have_key('model')
    expect(snapshot.sha256).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'does not let mutation of the reader DTO change the captured original or fingerprint' do
    snapshot = capture
    digest = snapshot.sha256
    analysis.fetch(:payload_completo).fetch('assuntos_abordados').first.replace('SYNTHETIC later change')
    expect(snapshot.data.dig('payload_completo', 'assuntos_abordados')).to eq(['SYNTHETIC service'])
    expect(snapshot.sha256).to eq(digest)
    expect { snapshot.data['nota_final'] = 100 }.to raise_error(FrozenError)
    expect { snapshot.data.fetch('texto_transcrito').replace('x') }.to raise_error(FrozenError)
    expect { snapshot.recommendations.first['text'] = 'x' }.to raise_error(FrozenError)
  end

  it 'fingerprints the same native JSON independently of top-level symbol or object-key order' do
    original = capture
    shuffled = analysis.to_a.reverse.to_h.deep_stringify_keys
    shuffled['payload_completo'] = shuffled.fetch('payload_completo').to_a.reverse.to_h
    expect(capture(shuffled).data).to eq(original.data)
    expect(capture(shuffled).sha256).to eq(original.sha256)
  end

  it 'does not reorder the original themes or suggestions when canonicalizing object keys' do
    first = capture
    analysis[:payload_completo]['assuntos_abordados'] << 'SYNTHETIC second theme'
    second = capture
    expect(second.sha256).not_to eq(first.sha256)
    expect(second.data.dig('payload_completo', 'assuntos_abordados')).to eq(['SYNTHETIC service', 'SYNTHETIC second theme'])
  end

  it 'does not treat absent and actual zero confidence as equivalent source evidence' do
    unknown = capture
    analysis[:confianca_transcricao] = 0
    known_zero = capture
    expect(known_zero.sha256).not_to eq(unknown.sha256)
    expect(known_zero.data.fetch('confianca_transcricao')).to eq(0)
  end

  it 'projects stable suggestion identifiers without creating operational actions or changing the original array' do
    original = analysis.deep_dup
    first = capture
    expect(first.recommendations.sole).to include('category' => 'oportunidades_melhoria', 'text' => 'SYNTHETIC optional suggestion')
    expect(first.recommendations.sole.fetch('id')).to match(/\A[0-9a-f]{64}\z/)
    expect(first.recommendations.sole.keys).to contain_exactly('id', 'category', 'text')
    expect(capture.recommendations).to eq(first.recommendations)
    expect(analysis).to eq(original)
  end

  it 'keeps a current native scalar suggestion as one suggestion without splitting or executing it' do
    analysis[:payload_completo]['oportunidades_melhoria'] = 'SYNTHETIC single original suggestion'
    snapshot = capture
    expect(snapshot.recommendations.sole.fetch('text')).to eq('SYNTHETIC single original suggestion')
    expect(snapshot.data.dig('payload_completo', 'oportunidades_melhoria')).to eq('SYNTHETIC single original suggestion')
  end

  it 'validates human selection against an actual unchanged private source snapshot' do
    snapshot = capture
    values = { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC human summary', 'adjusted_themes' => [],
               'recommendation_ids' => snapshot.recommendations.pluck('id'), 'justification' => 'SYNTHETIC explicit reason',
               'expected_revision' => 0, 'request_id' => SecureRandom.uuid, 'expected_source_sha256' => snapshot.sha256 }
    input = JrcContactCenter::QualityReviewInput.new(values)
    expect(input.validate_source!(actual_sha256: snapshot.sha256, available_recommendation_ids: snapshot.recommendations.pluck('id'))).to be(input)
    analysis[:resumo_conversa] = 'SYNTHETIC changed source'
    expect do
      changed = capture
      input.validate_source!(actual_sha256: changed.sha256, available_recommendation_ids: changed.recommendations.pluck('id'))
    end.to raise_error(JrcContactCenter::OperationError, 'quality_review_source_changed')
    expect(snapshot.data.fetch('resumo_conversa')).to eq('SYNTHETIC original summary')
  end

  [nil, false, [], 'not-a-source'].each do |invalid|
    it "rejects a missing or malformed source DTO #{invalid.inspect}" do
      expect { capture(invalid) }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
    end
  end

  %i[id chamada_id call_id payload_completo].each do |field|
    it "requires an actual persisted native source identity and payload in #{field}" do
      analysis.delete(field)
      expect { capture }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
    end
  end

  it 'does not allow a different call ID to become the source of the current review' do
    expect { capture(call_id: 'SYNTHETIC-another-call') }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
  end

  it 'rejects ambiguous top-level identities rather than silently keeping one spelling' do
    analysis['id'] = 'SYNTHETIC-conflicting-analysis'
    expect { capture }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
  end

  %w[account_id user_id unit_id recording_url source_sha256].each do |field|
    it "rejects fields outside the actual native analysis projection #{field}" do
      analysis[field] = 'untrusted'
      expect { capture }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
    end
  end

  [false, {}, [nil], Array.new(41, 'SYNTHETIC'), ['x' * 4_001]].each do |invalid|
    it "does not silently discard an invalid suggestion projection #{invalid.inspect.to_s.first(60)}" do
      analysis[:payload_completo]['oportunidades_melhoria'] = invalid
      expect { capture }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
    end
  end

  it 'preserves the native Supabase identifier length and syntax without shortening a valid call identity' do
    analysis[:call_id] = "SYNTHETIC-#{'x' * 245}"
    expect(capture(call_id: analysis.fetch(:call_id)).data.fetch('call_id')).to eq(analysis.fetch(:call_id))
    analysis[:call_id] += 'x'
    expect { capture(call_id: analysis.fetch(:call_id)) }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
  end

  it 'bounds snapshot bytes without truncating the original transcript or fabricating a new version' do
    analysis[:texto_transcrito] = 'x' * 1.megabyte
    expect { capture }.to raise_error(JrcContactCenter::OperationError, 'quality_analysis_source_unavailable')
  end
end
