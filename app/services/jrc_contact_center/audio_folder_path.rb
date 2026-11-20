# frozen_string_literal: true

# The caller supplies its native authorized relation, not a caller-provided account or unit.
class JrcContactCenter::AudioFolderPath
  def initialize(folder:, scope:)
    @folder = folder
    @scope = scope
  end

  def call
    rows = JrcContactCenter::AudioFolder.connection.select_all(query).to_a
    raise JrcContactCenter::OperationError, 'invalid_audio_folder_hierarchy' if rows.any? { |row| row.fetch('repeated_id').present? }
    raise ActiveRecord::RecordNotFound if rows.empty? || rows.first.fetch('parent_id').present?

    rows.map { |row| { 'id' => row.fetch('id').to_s, 'name' => row.fetch('name') } }
  end

  private

  def query
    relation = @scope.where(account_id: @folder.account_id, unit_id: @folder.unit_id).except(:includes).reorder(nil).reselect(:id, :parent_id, :name)
    id = JrcContactCenter::AudioFolder.connection.quote(@folder.id)
    <<~SQL.squish
      WITH RECURSIVE authorized AS (#{relation.to_sql}), hierarchy AS (
        SELECT id, parent_id, name, 0 AS depth, ARRAY[id] AS visited, false AS cycle_detected
        FROM authorized WHERE id = #{id}
        UNION ALL
        SELECT parent.id, parent.parent_id, parent.name, child.depth + 1,
          child.visited || parent.id, parent.id = ANY(child.visited)
        FROM authorized parent JOIN hierarchy child ON parent.id = child.parent_id
        WHERE NOT child.cycle_detected
      )
      SELECT id, parent_id, name, CASE WHEN cycle_detected THEN id END AS repeated_id FROM hierarchy ORDER BY depth DESC
    SQL
  end
end
