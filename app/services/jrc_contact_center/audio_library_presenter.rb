# frozen_string_literal: true

class JrcContactCenter::AudioLibraryPresenter
  def self.asset(record)
    latest = record.latest_version
    fields = record.as_json(only: %i[name description purpose created_at updated_at])
    fields.merge('id' => record.id.to_s, 'unit_id' => record.unit_id.to_s, 'folder_id' => record.folder_id&.to_s,
                 'folder_name' => record.folder&.name, 'revision' => JrcContactCenter::AudioAssetRevision.token(record, version: latest),
                 'latest_version' => latest && version(latest))
  end

  def self.version(record)
    record.as_json(only: %i[number source_kind file_name content_type byte_size sha256 created_at])
          .merge('id' => record.id.to_s, 'audio_asset_id' => record.audio_asset_id.to_s, 'unit_id' => record.unit_id.to_s,
                 'created_by_name' => record.created_by.name, 'security_state' => 'not_verified', 'ready' => false)
  end

  def self.inspection(record)
    fields = record.as_json(only: %i[attempt state probe_state expected_sha256 observed_sha256 scanner_adapter
                                     decoder_version observed_at created_at])
    fields.merge('id' => record.id.to_s, 'audio_version_id' => record.audio_version_id.to_s, 'unit_id' => record.unit_id.to_s,
                 'metadata' => record.metadata.slice(*JrcContactCenter::AudioMediaMetadata::FIELDS),
                 'created_by_name' => record.created_by.name, 'ready' => record.ready?)
  end
end
