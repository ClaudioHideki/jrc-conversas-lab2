# frozen_string_literal: true

require_relative 'jrc_call_center_legacy_audio_receipt'

# Only called behind SyntheticPauseSeed's owned PostgreSQL/Redis runner guard.
class JrcContactCenter::SyntheticAudioFolderSeed
  def self.call(account:, queues:, member:)
    folders = create_folders(account, queues.first.unit)
    hidden = JrcContactCenter::AudioFolder.create!(account: account, unit: queues.last.unit, name: 'SYNTHETIC inaccessible library')
    {
      audio_folder_id: folders.first.id.to_s, audio_folder_name: folders.first.name,
      audio_destination_id: folders.last.id.to_s, audio_destination_name: folders.last.name,
      denied_audio_folder_id: hidden.id.to_s
    }.merge(legacy_identifiers(account, queues.first.unit, member)).merge(metadata_identifiers(account, folders[-2]))
  end

  def self.create_folders(account, unit)
    (1..22).map do |number|
      JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: format('SYNTHETIC folder %02d', number))
    end
  end

  def self.metadata_identifiers(account, folder)
    asset = JrcContactCenter::AudioAsset.create!(account: account, unit: folder.unit, folder: folder,
                                                 name: 'SYNTHETIC metadata only organization')
    { metadata_audio_id: asset.id.to_s, metadata_audio_name: asset.name,
      metadata_audio_folder_id: folder.id.to_s, metadata_audio_folder_name: folder.name }
  end

  def self.legacy_identifiers(account, unit, member)
    access = JrcContactCenter::AudioLibraryAccess.new(context: { account: account, user: member.user, account_user: member })
    {
      technical_legacy_audio_id: legacy_receipt(access, unit, 'technical', 16).audio_asset_id.to_s,
      preview_legacy_audio_id: legacy_receipt(access, unit, 'preview', 32_000).audio_asset_id.to_s
    }
  end

  def self.legacy_receipt(access, unit, name, samples)
    bytes = "RIFF#{[samples + 36].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[samples].pack('V')}#{"\0" * samples}".b
    Tempfile.create(['SYNTHETIC-legacy-audio', '.wav']) do |file|
      file.binmode
      file.write(bytes)
      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: "SYNTHETIC-#{name}.wav", type: 'audio/wav')
      JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access).create!(
        unit_id: unit.id, attributes: { name: "SYNTHETIC legacy #{name}" }, file: upload, key: SecureRandom.uuid
      )
    end
  end
  private_class_method :create_folders, :metadata_identifiers, :legacy_identifiers, :legacy_receipt
end
