# frozen_string_literal: true

require 'digest'
require 'json'

# Private value captured ONLY after native call/recording authorization and a scoped source read.
# A fingerprint is not authority. This class neither fetches nor changes provider data.
class JrcContactCenter::QualityAnalysisSnapshot
  FIELDS = %w[id chamada_id call_id status nota_final classificacao_ligacao sentimento_cliente sentimento_atendente
              temperatura_conversa risco_churn risco_reclamacao resumo_conversa alerta_supervisao motivo_alerta
              confianca_transcricao observacao_transcricao texto_transcrito payload_completo created_at].freeze
  SUGGESTION_FIELDS = %w[oportunidades_melhoria treinamento_recomendado].freeze
  attr_reader :data, :sha256, :recommendations

  def initialize(analysis:, authorized_call_id:)
    @data = private_json_copy(analysis)
    validate_identity!(authorized_call_id)
    @recommendations = suggestions
    canonical = { 'snapshot_schema' => 1, 'source' => 'jrc_voice_quality', 'analysis' => sorted(@data) }
    @sha256 = Digest::SHA256.hexdigest(JSON.generate(canonical)).freeze
    deep_freeze(@data)
    deep_freeze(@recommendations)
  rescue JSON::GeneratorError, JSON::ParserError, ArgumentError, TypeError, Encoding::UndefinedConversionError
    unavailable!
  end

  private

  def unavailable!
    raise JrcContactCenter::OperationError, 'quality_analysis_source_unavailable'
  end

  def private_json_copy(analysis)
    unavailable! unless source_keys?(analysis)

    json = JSON.generate(analysis, max_nesting: 32)
    unavailable! unless json.bytesize <= 1.megabyte

    JSON.parse(json, max_nesting: 32)
  end

  def source_keys?(analysis)
    return false unless analysis.is_a?(Hash)

    keys = analysis.keys
    keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) } && keys.map(&:to_s).uniq.length == keys.length
  end

  def identifier?(value)
    return value.positive? && value.bit_length <= 63 if value.is_a?(Integer)

    value.is_a?(String) && value.valid_encoding? && value.match?(/\A[0-9A-Za-z_.:-]{1,255}\z/)
  end

  def validate_identity!(authorized_call_id)
    valid = (@data.keys - FIELDS).empty? && @data.fetch('payload_completo', nil).is_a?(Hash)
    valid &&= %w[id chamada_id call_id].all? { |field| identifier?(@data[field]) }
    valid &&= identifier?(authorized_call_id) && @data.fetch('call_id').to_s == authorized_call_id.to_s
    unavailable! unless valid
  end

  def suggestions
    rows = SUGGESTION_FIELDS.flat_map do |field|
      suggestion_values(@data.fetch('payload_completo')[field]).map do |text|
        id = Digest::SHA256.hexdigest(JSON.generate([field, text]))
        { 'id' => id, 'category' => field, 'text' => text }
      end
    end
    rows.uniq { |row| row.fetch('id') }
  end

  def suggestion_values(value)
    return [] if value.nil? || value == ''

    items = value.is_a?(Array) ? value : [value]
    valid = items.length <= 40 && items.all? { |text| suggestion_text?(text) }
    unavailable! unless valid

    items
  end

  def suggestion_text?(text)
    text.is_a?(String) && text.valid_encoding? && text.bytesize.between?(1, 4_000) && text.strip.present?
  end

  def sorted(value)
    case value
    when Hash then value.keys.sort.index_with { |key| sorted(value.fetch(key)) }
    when Array then value.map { |child| sorted(child) }
    else value
    end
  end

  def deep_freeze(value)
    case value
    when Hash
      value.each do |key, child|
        key.freeze
        deep_freeze(child)
      end
    when Array
      value.each { |child| deep_freeze(child) }
    end
    value.freeze
  end
end
