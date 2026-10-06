class JrcRelationship::SentimentMetric
  VALUES = { 'positivo' => 100, 'positive' => 100, 'neutro' => 60, 'neutral' => 60,
             'negativo' => 20, 'negative' => 20, 'critico' => 0, 'critical' => 0 }.freeze
  def self.call(rows)
    observations = rows.filter_map do |id, value|
      next unless value.is_a?(Hash)
      label = value['label'] || value['sentimento_cliente'] || value['sentiment']
      normalized = VALUES[label.to_s.downcase]
      next if normalized.nil?
      { message_id: id, label: label, normalized: normalized }
    end
    { raw: observations, normalized: observations.empty? ? nil : observations.sum { |row| row[:normalized] }.to_f / observations.size,
      evidence: observations.empty? ? 'No recognized sentiment in authorized native messages' : 'Existing analyzed public messages; no new sentiment inference',
      source_ids: observations.map { |row| row[:message_id] } }
  end
end
