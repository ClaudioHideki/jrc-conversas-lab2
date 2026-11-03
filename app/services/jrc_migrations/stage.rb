class JrcMigrations::Stage
  MAX_ROWS = 500
  MAX_BYTES = 2.megabytes

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def call(source:, domain:, rows:, mapping:, file_name: nil)
    JrcMigrations::Access.authorize!(@account, @user)
    fields = JrcMigrations::Catalog::FIELDS[domain]
    raise JrcMigrations::Error, 'UNSUPPORTED_DOMAIN' unless fields

    validate!(source, rows, mapping, fields)
    normalized = rows.map { |row| normalize(row.stringify_keys, mapping.stringify_keys, fields) }
    validate_ids!(normalized)
    attributes = { source: source, domain: domain, field_mapping: mapping, file_name: file_name.to_s.first(255).presence }
    persist!(rows: rows, normalized: normalized, attributes: attributes)
  end

  private

  def validate_ids!(normalized)
    ids = normalized.pluck('legacy_id')
    raise JrcMigrations::Error, 'SOURCE_ID_REQUIRED' if ids.any? { |id| !id.is_a?(String) || id.blank? || id.length > 255 }
    raise JrcMigrations::Error, 'DUPLICATE_SOURCE_ID' unless ids.uniq == ids
  end

  def persist!(rows:, normalized:, attributes:)
    @account.with_lock('FOR NO KEY UPDATE') do
      JrcMigrations::Access.authorize!(@account, @user, lock: true)
      batch = JrcMigrations::Batch.create!(attributes.merge(account: @account, created_by: @user, source_digest: JrcMigrations::Catalog.digest(rows)))
      rows.zip(normalized).each do |raw, data|
        batch.items.create!(account: @account, legacy_id: data['legacy_id'], raw_data: raw, normalized_data: data,
                            source_digest: JrcMigrations::Catalog.digest(data))
      end
      JrcMigrations::Event.record!(batch: batch, user: @user, action: 'STAGED', metadata: { source_digest: batch.source_digest })
      batch
    end
  end

  def validate!(source, rows, mapping, fields)
    source_valid = source.is_a?(String) && /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,99}\z/.match?(source)
    raise JrcMigrations::Error, 'INVALID_STAGING_INPUT' unless source_valid && valid_rows?(rows) && valid_mapping?(mapping, fields)
  end

  def valid_rows?(rows)
    return false unless rows.is_a?(Array) && rows.size.between?(1, MAX_ROWS)

    rows.all? { |row| row.is_a?(Hash) && row.size <= 100 } && rows.to_json.bytesize <= MAX_BYTES
  end

  def valid_mapping?(mapping, fields)
    return false unless mapping.is_a?(Hash) && (mapping.keys.map(&:to_s) - fields).empty?

    mapping.values.all? { |value| value.is_a?(String) && value.length <= 255 }
  end

  def normalize(row, mapping, fields)
    fields.each_with_object({}) do |field, result|
      column = mapping.fetch(field, field)
      result[field] = row[column] if row.key?(column)
    end
  end
end
