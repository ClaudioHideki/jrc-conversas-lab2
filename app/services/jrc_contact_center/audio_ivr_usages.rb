# frozen_string_literal: true

# Current local draft heads only. Historical references remain in immutable IVR versions.
# Neither a local reference nor its absence proves any live provider configuration.
class JrcContactCenter::AudioIvrUsages
  attr_reader :asset

  def initialize(context:, asset_id:)
    @library = JrcContactCenter::AudioLibraryAccess.new(context: context)
    @asset = @library.asset(asset_id)
    @drafts = JrcContactCenter::IvrDraftAccess.new(context: context).relation.where(unit_id: asset.unit_id)
  end

  def relation
    versions = JrcContactCenter::IvrDraftVersion.where(account: @library.account, ivr_draft_id: @drafts.select(:id))
    versions = versions.where(<<~SQL.squish)
      NOT EXISTS (
        SELECT 1 FROM jrc_contact_center_ivr_draft_versions newer
        WHERE newer.account_id = jrc_contact_center_ivr_draft_versions.account_id
          AND newer.ivr_draft_id = jrc_contact_center_ivr_draft_versions.ivr_draft_id
          AND newer.revision > jrc_contact_center_ivr_draft_versions.revision
      )
    SQL
    reference = { nodes: [{ audio_reference: { asset_id: asset.id.to_s } }] }
    versions.where('definition @> ?::jsonb', JSON.generate(reference))
  end

  def present(version)
    references = version.definition.fetch('nodes').filter_map do |node|
      reference = node['audio_reference']
      next unless node['type'] == 'menu' && reference.is_a?(Hash) && reference['asset_id'] == asset.id.to_s

      { node_id: node.fetch('id'), audio_version_id: reference.fetch('version_id'), sha256: reference.fetch('sha256') }
    end
    { draft_id: version.ivr_draft_id.to_s, draft_revision: version.revision, name: version.name,
      status: version.status, unit_id: asset.unit_id.to_s, references: references,
      local_only: true, provider_applied: false }
  end
end
