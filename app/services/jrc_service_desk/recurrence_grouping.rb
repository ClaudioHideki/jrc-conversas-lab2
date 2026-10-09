# frozen_string_literal: true

class JrcServiceDesk::RecurrenceGrouping
  def self.call(rows, definition)
    keys = definition.fetch('group_by')
    normalized = rows.uniq { |row| row.fetch('id') }.map do |row|
      row.merge('normalized_title' => row.fetch('title').unicode_normalize(:nfkc).downcase.gsub(/[[:space:]]+/, ' ').strip)
    end
    # Missing classification is not evidence that unrelated tickets have the same defect.
    classified = normalized.select { |row| keys.all? { |key| !row[key].nil? && row[key] != '' } }
    groups = classified.group_by { |row| keys.map { |key| row.fetch(key) } }
    groups.filter_map do |signature, tickets|
      next if tickets.size < definition.fetch('minimum_occurrences')

      { key: JrcServiceDesk::CanonicalJson.digest(keys.zip(signature).to_h), count: tickets.size,
        ticket_ids: tickets.map { |row| row.fetch('id').to_s }.sort_by(&:to_i),
        unlinked_ticket_ids: tickets.reject { |row| row['incident_id'] }.map { |row| row.fetch('id').to_s }.sort_by(&:to_i),
        matching_fields: keys, method: 'exact_structured_match_human_confirmation_required' }
    end.sort_by { |row| [-row[:count], row[:key]] }
  end
end
