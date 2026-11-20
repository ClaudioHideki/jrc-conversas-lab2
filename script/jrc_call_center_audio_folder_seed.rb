# frozen_string_literal: true

# Only called behind SyntheticPauseSeed's owned PostgreSQL/Redis runner guard.
class JrcContactCenter::SyntheticAudioFolderSeed
  def self.call(account:, queues:)
    folders = (1..22).map do |number|
      JrcContactCenter::AudioFolder.create!(account: account, unit: queues.first.unit, name: format('SYNTHETIC folder %02d', number))
    end
    hidden = JrcContactCenter::AudioFolder.create!(account: account, unit: queues.last.unit, name: 'SYNTHETIC inaccessible library')
    {
      audio_folder_id: folders.first.id.to_s, audio_folder_name: folders.first.name,
      audio_destination_id: folders.last.id.to_s, audio_destination_name: folders.last.name,
      denied_audio_folder_id: hidden.id.to_s
    }
  end
end
