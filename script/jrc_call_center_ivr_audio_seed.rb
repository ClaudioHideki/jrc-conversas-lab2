# Only an owned synthetic fixture: reproduce a genuinely unverified legacy version without a fake ready inspection.
require_relative 'jrc_call_center_legacy_audio_receipt'

class JrcContactCenter::SyntheticIvrAudioSeed
  def self.call(targets:)
    JrcContactCenter::SyntheticAudioStorageGuard.call
    targets.each_value do |target|
      version = version_for(target)
      target[:unverified_audio_ref] = { asset_id: version.audio_asset_id.to_s, version_id: version.id.to_s, sha256: version.sha256 }
    end
  end

  def self.version_for(target)
    account = Account.find(target.fetch(:account_id))
    raise 'Owned synthetic IVR account required' unless account.name.start_with?('SYNTHETIC IVR ')

    actor = account.users.find_by!(email: target.fetch(:administrator).fetch('uid'))
    member = account.account_users.find_by!(user: actor)
    access = JrcContactCenter::AudioLibraryAccess.new(context: { account: account, user: actor, account_user: member })
    legacy_version(access, target.fetch(:allowed_unit_id))
  end

  def self.legacy_version(access, unit_id)
    bytes = "RIFF#{[52].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[16].pack('V')}#{"\0" * 16}".b
    Tempfile.create(['SYNTHETIC-unverified-IVR', '.wav']) do |file|
      file.binmode
      file.write(bytes)
      file.rewind
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'SYNTHETIC-unverified-IVR.wav', type: 'audio/wav')
      JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access).create!(
        unit_id: unit_id, attributes: { name: 'SYNTHETIC legacy unobserved IVR sample' }, file: upload, key: SecureRandom.uuid
      )
    end
  end
  private_class_method :version_for, :legacy_version
end
