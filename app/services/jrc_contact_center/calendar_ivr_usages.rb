# frozen_string_literal: true

# Read only: latest local native versions, using the same head-selection semantics as AudioIvrUsages.
# Historical pins remain immutable. A local reference does not attest any provider configuration.
class JrcContactCenter::CalendarIvrUsages
  def initialize(context:, unit_id:, calendar_id:)
    @context = context.slice(:account, :account_user, :user)
    @unit_id = unit_id
    @calendar_id = calendar_id
  end

  def call(page: 1, per_page: 10, q: '', status: 'all')
    refresh!
    filters!(q, status)
    page = page!(page, 1_000_000)
    limit = page!(per_page, 20)
    rows = filtered(q, status)
    total = rows.count
    items = rows.order(created_at: :desc, id: :desc).offset((page - 1) * limit).limit(limit).map { |row| present(row) }
    { items: items, meta: { page: page, per_page: limit, total: total, pages: (total.to_f / limit).ceil },
      calendar_id: @calendar_id, calendar_digest: @digest, unit_id: @unit_id.to_s,
      local_only: true, pabx_confirmed: false, coverage: 'current_local_ivr_drafts_only', provider_configuration_verified: false }
  end

  private

  def refresh!
    catalog = JrcContactCenter::CalendarCatalog.new(context: @context, unit_id: @unit_id)
    entry = catalog.find!(@calendar_id)
    @calendar_id = entry.fetch('id')
    @digest = JrcContactCenter::ConfigurationRevision.content_token(entry)
    scope = JrcContactCenter::IvrDraftAccess.new(context: @context)
    scope.access.units.find(@unit_id)
    @drafts = scope.relation.where(unit_id: @unit_id)
  end

  def filters!(query, status)
    valid = query.is_a?(String) && query.length <= 100 && %w[all draft archived].include?(status)
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_filter' unless valid
  end

  def page!(value, maximum)
    result = JrcServiceDesk::Input.id(value)
    raise ArgumentError if result > maximum

    result
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_contact_center_calendar_filter'
  end

  def latest_versions
    JrcContactCenter::IvrDraftVersion.where(account: @context.fetch(:account), ivr_draft_id: @drafts.select(:id)).where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM jrc_contact_center_ivr_draft_versions newer
        WHERE newer.account_id = jrc_contact_center_ivr_draft_versions.account_id
          AND newer.ivr_draft_id = jrc_contact_center_ivr_draft_versions.ivr_draft_id
          AND newer.revision > jrc_contact_center_ivr_draft_versions.revision
      )
    SQL
  end

  def filtered(query, status)
    reference = { schema_version: 3, nodes: [{ type: 'calendar', calendar_reference: { calendar_id: @calendar_id } }] }
    rows = latest_versions.where('definition @> ?::jsonb', JSON.generate(reference))
    rows = rows.where(status: status) unless status == 'all'
    text = query.strip
    rows = rows.where('name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(text)}%") if text.present?
    rows
  end

  def present(version)
    references = version.definition.fetch('nodes').filter_map do |node|
      reference = node['calendar_reference']
      next unless node['type'] == 'calendar' && reference.is_a?(Hash) && reference['calendar_id'] == @calendar_id

      { node_id: node.fetch('id'), sha256: reference.fetch('sha256'), unit_revision: reference.fetch('unit_revision'),
        calendar_changed: reference.fetch('sha256') != @digest }
    end
    { draft_id: version.ivr_draft_id.to_s, draft_revision: version.revision, version_id: version.id.to_s,
      name: version.name, status: version.status, unit_id: @unit_id.to_s, references: references,
      local_only: true, provider_applied: false }
  end
end
