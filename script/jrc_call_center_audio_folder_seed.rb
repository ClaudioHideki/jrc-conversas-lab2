# frozen_string_literal: true

require_relative 'jrc_call_center_legacy_audio_receipt'

# Only called behind SyntheticPauseSeed's owned PostgreSQL/Redis runner guard.
class JrcContactCenter::SyntheticAudioFolderSeed
  def self.call(account:, queues:, member:)
    folders = (1..22).map do |number|
      JrcContactCenter::AudioFolder.create!(account: account, unit: queues.first.unit, name: format('SYNTHETIC folder %02d', number))
    end
    hidden = JrcContactCenter::AudioFolder.create!(account: account, unit: queues.last.unit, name: 'SYNTHETIC inaccessible library')
    payload = {
      audio_folder_id: folders.first.id.to_s, audio_folder_name: folders.first.name,
      audio_destination_id: folders.last.id.to_s, audio_destination_name: folders.last.name,
      denied_audio_folder_id: hidden.id.to_s
    }
    access = JrcContactCenter::AudioLibraryAccess.new(context: { account: account, user: member.user, account_user: member })
    payload[:technical_legacy_audio_id] = legacy_receipt(access, queues.first.unit, 'technical', 16).audio_asset_id.to_s
    payload[:preview_legacy_audio_id] = legacy_receipt(access, queues.first.unit, 'preview', 32_000).audio_asset_id.to_s
    payload
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
  private_class_method :legacy_receipt
end
