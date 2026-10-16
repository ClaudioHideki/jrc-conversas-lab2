# Response field paths are explicit provisional configuration, not a claim that
# a populated vendor CDR has been observed. No duration/billsec is synthesized.
class Pabx::Contract
  DIRECTIONS = { 'IN' => 'inbound', 'OUT' => 'outbound', 'INTRA' => 'local', 'API' => 'api' }.freeze
  STATUSES = { 'ANSWERED' => 'answered', 'NO ANSWER' => 'unanswered', 'BUSY' => 'busy', 'CONGESTION' => 'congestion' }.freeze

  def self.at(payload, path)
    path.to_s.split('.').reduce(payload) { |value, key| value.is_a?(Hash) ? value[key] : nil }
  end

  def self.recording_link?(value)
    value.is_a?(String) && value.bytesize <= 1024 && !value.include?('..') &&
      %r{\A/var/spool/asterisk/monitor/(?:[0-9A-Za-z_-]+/)*[0-9A-Za-z_.-]+\z}.match?(value)
  end

  def initialize(settings)
    @settings = settings
    @fields = settings.data.fetch('cdr_fields', {})
  end

  def page(payload)
    raise Pabx::Error, 'INVALID_RESPONSE' unless payload.is_a?(Hash)

    total = self.class.at(payload, @settings.value('cdr_total_path', 'data.total'))
    raise Pabx::Error, 'INVALID_PAGINATION' unless total.is_a?(Integer) && total >= 0
    rows = self.class.at(payload, @settings.value('cdr_rows_path', 'resultado.data'))
    return { total: 0, rows: [] } if total.zero? && (rows.nil? || rows == [])
    raise Pabx::Error, 'CDR_MAPPING_PENDING' unless rows.is_a?(Array) && @fields.values_at('unique_id', 'tenant', 'extension', 'started_at').all?(&:present?)

    raise Pabx::Error, 'INVALID_PAGINATION' if rows.size > total
    current_page = self.class.at(payload, 'resultado.current_page')
    if current_page && (!current_page.is_a?(Integer) || current_page < 1)
      raise Pabx::Error, 'INVALID_PAGINATION'
    end
    { total: total, rows: rows.map { |row| normalize(row) }, current_page: current_page }
  end

  def normalize(row)
    raise Pabx::Error, 'INVALID_RESPONSE' unless row.is_a?(Hash)
    raise Pabx::Error, 'TENANT_MISMATCH' unless read(row, 'tenant').to_s == @settings.data.fetch('expected_tenant').to_s

    unique_id = read(row, 'unique_id').to_s
    raise Pabx::Error, 'INVALID_CDR_ID' unless /\A[0-9A-Za-z_.:-]{1,255}\z/.match?(unique_id)
    extension = read(row, 'extension').to_s
    tenant = @settings.data.fetch('expected_tenant').to_s
    if @settings.value('cdr_extension_identity', 'plain') == 'tenant_prefix'
      raise Pabx::Error, 'INVALID_EXTENSION' unless extension.start_with?(tenant)
      extension = extension.delete_prefix(tenant)
    end
    raise Pabx::Error, 'INVALID_EXTENSION' unless /\A[0-9]{1,20}\z/.match?(extension)

    identity = { external_unique_id: unique_id, extension: extension, caller: party(read(row, 'caller')), callee: party(read(row, 'callee')) }
    identity.merge(timing(row)).merge(outcome(row))
  end

  private

  def read(row, key)
    self.class.at(row, @fields[key]) if @fields[key]
  end

  def party(value)
    value.to_s[/\A\+?[0-9]{1,32}\z/] if value
  end

  def timing(row)
    raw = read(row, 'started_at')
    started = Time.iso8601(raw) if raw.is_a?(String) && /(?:Z|[+-][0-9]{2}:[0-9]{2})\z/.match?(raw)
    raise Pabx::Error, 'INVALID_CDR_TIME' unless started

    { started_at: started, duration_seconds: seconds(read(row, 'duration_seconds')), answered_seconds: seconds(read(row, 'answered_seconds')) }
  rescue ArgumentError
    raise Pabx::Error, 'INVALID_CDR_TIME', cause: nil
  end

  def seconds(value)
    return if value.nil?
    raise Pabx::Error, 'INVALID_DURATION' unless value.is_a?(Integer) && value >= 0

    value
  end

  def outcome(row)
    reference = read(row, 'recording_reference')
    safe_reference = reference.to_s if reference.is_a?(String) && /\A[0-9A-Za-z_.:-]{1,255}\z/.match?(reference) && !reference.include?('..')
    if @settings.value('recording_lookup', '') == 'link'
      safe_reference = self.class.recording_link?(reference) ? reference : nil
    end
    { direction: DIRECTIONS.fetch(read(row, 'direction'), 'unknown'), status: STATUSES.fetch(read(row, 'status'), 'unknown'),
      has_recording: read(row, 'has_recording') == 'S', recording_reference: safe_reference }
  end
end
