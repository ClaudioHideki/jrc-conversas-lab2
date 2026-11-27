# frozen_string_literal: true

# No media URL, raw transcript, provider credential or inferred model provenance is returned.
class JrcContactCenter::QualityReviewPresentation
  ORIGINAL_FIELDS = %w[id chamada_id call_id status nota_final classificacao_ligacao sentimento_cliente sentimento_atendente
                       resumo_conversa confianca_transcricao created_at alerta_supervisao motivo_alerta].freeze
  THEME_FIELDS = %w[assuntos_abordados temas_principais].freeze

  def self.original(snapshot)
    payload = snapshot.data.fetch('payload_completo')
    snapshot.data.slice(*ORIGINAL_FIELDS).merge(
      'model' => nil, 'model_provenance' => 'not_supplied_by_native_source', 'sentiment_confidence' => nil,
      'themes' => THEME_FIELDS.flat_map { |key| Array(payload[key]) }.select { |value| value.is_a?(String) }.uniq,
      'recommendations' => snapshot.recommendations
    )
  end

  def self.revision(row)
    return unless row

    {
      id: row.id.to_s, revision: row.revision, source_sha256: row.source_sha256, actor_id: row.actor_user_id.to_s,
      created_at: row.created_at.iso8601(6), request_id: row.request_key,
      origin: 'human', original: row.original_analysis, values: row.reviewed_values
    }
  end
end
