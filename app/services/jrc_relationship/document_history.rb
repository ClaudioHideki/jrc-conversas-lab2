# Projects the existing audit log through current native document access.
class JrcRelationship::DocumentHistory
  ACTIONS = { 'metadata' => 'document_metadata_updated', 'version' => 'document_uploaded' }.freeze

  def initialize(context)
    @context = context
  end

  def scope(document_id:, kind: nil)
    @document = JrcRelationship::CustomerDocuments.new(@context).scope.find(document_id)
    actions = kind.present? ? [ACTIONS.fetch(kind)] : ACTIONS.values
    JrcCrm::AuditEvent.where(account_id: @context.account.id, resource_type: @document.class.name, resource_id: @document.id,
                             event_type: 'relationship_updated').where("metadata ->> 'action' IN (?)", actions)
  end

  def present(records)
    rows = records.to_a
    load_users(rows)
    version_ids = rows.filter_map { |row| identifier(values(row.to_value)['version_id']) }
    versions = @document.versions.where(account_id: @context.account.id, id: version_ids).index_by(&:id)
    rows.map { |row| event(row, versions) }
  end

  private

  def load_users(rows)
    ids = rows.flat_map do |row|
      [row.actor_type == 'User' ? row.actor_id : nil, values(row.from_value)['responsible_id'], values(row.to_value)['responsible_id']]
    end
    ids = ids.filter_map { |value| identifier(value) }
    @users = @context.account.users.where(id: ids.uniq).pluck(:id, :name).to_h
  end

  def event(row, versions)
    after = values(row.to_value)
    version = versions[identifier(after['version_id'])]
    { id: row.id, action: row.metadata['action'], at: row.created_at,
      actor: user(row.actor_type == 'User' ? row.actor_id : nil),
      before: metadata(row.from_value), after: metadata(row.to_value), reason: reason(version ? version.change_reason : after['reason']),
      version: version && { id: version.id, number: version.number, valid_until: version.valid_until } }
  end

  def metadata(value)
    attributes = values(value)
    status = attributes['status'] if %w[active archived].include?(attributes['status'])
    key = attributes['requirement_key']
    key = nil unless key.is_a?(String) && key.match?(/\A[a-z][a-z0-9_-]{0,59}\z/)
    responsible = attributes['responsible_id']
    { responsible: responsible.nil? ? { state: 'unassigned' } : user(responsible), status: status, requirement_key: key }
  end

  def user(value)
    id = identifier(value)
    return { state: 'unavailable' } unless id && @users.key?(id)

    { state: 'available', id: id, name: @users.fetch(id) }
  end

  def values(value)
    value.is_a?(Hash) ? value : {}
  end

  def identifier(value)
    return unless value.is_a?(Integer) || value.is_a?(String)

    id = Integer(value.to_s, 10)
    id if id.between?(1, 9_223_372_036_854_775_807)
  rescue ArgumentError
    nil
  end

  def reason(value)
    value.first(500) if value.is_a?(String)
  end
end
