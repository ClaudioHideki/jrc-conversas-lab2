# frozen_string_literal: true

require_relative 'owned_recording_media'

# Only the remote analysis read is synthetic. Native auth, exact recording/call correlation, SQL revisions and audits remain real.
# Loaded by the alternate owned Rack entry only, never by the application or a production initializer.
module SyntheticRecordedCallQuality
  def self.install!
    SyntheticRecordedCallMedia.validate_environment!
    JrcVoiceQuality::SupabaseClient.prepend(Source)
  end

  def self.analysis(account_id, call_id)
    SyntheticRecordedCallMedia.validate_environment!
    account = Account.find(account_id)
    marker = SyntheticRecordedCallMedia.control!(account)
    record = TelephonyCallRecord.where(account: account, id: marker.fetch('record_ids'), external_unique_id: call_id).sole
    valid = record.provider == Pabx::Settings::PROVIDER && record.external_tenant == '8' &&
            record.external_unique_id.start_with?("synthetic-recording-#{marker.fetch('nonce')}-")
    raise 'Only the exact owned native analysis source is available' unless valid

    JrcContactCenter::CallSession.where(account: account, provider: Pabx::Settings::PROVIDER, external_session_id: call_id).sole
    source(record)
  end

  def self.source(record)
    {
      'id' => "SYNTHETIC-analysis-#{record.id}", 'chamada_id' => "SYNTHETIC-original-#{record.id}", 'call_id' => record.external_unique_id,
      'status' => 'completed', 'sentimento_cliente' => 'positivo', 'classificacao_ligacao' => 'excelente', 'nota_final' => 0,
      'confianca_transcricao' => nil, 'resumo_conversa' => 'SYNTHETIC original immutable summary',
      'alerta_supervisao' => true, 'motivo_alerta' => 'SYNTHETIC explicit source signal independent of sentiment',
      'texto_transcrito' => 'SYNTHETIC original transcript never changed', 'created_at' => '2026-11-26T12:00:00Z',
      'payload_completo' => { 'assuntos_abordados' => ['SYNTHETIC service'], 'oportunidades_melhoria' => ['SYNTHETIC suggestion only'] }
    }
  end

  module Source
    def find_analysis(account_id:, call_id:)
      SyntheticRecordedCallQuality.analysis(account_id, call_id)
    end
  end
end
