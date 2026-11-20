# frozen_string_literal: true

require 'json'

# Composes the existing CAS protocol with the exact immutable library version. Not an access token.
class JrcContactCenter::AudioAssetRevision
  def self.token(asset, version:)
    if version
      valid = version.account_id == asset.account_id && version.unit_id == asset.unit_id && version.audio_asset_id == asset.id
      raise ActiveRecord::RecordNotFound unless valid
    end

    Digest::SHA256.hexdigest(JSON.generate([JrcContactCenter::ConfigurationRevision.token(asset), version&.id, version&.sha256]))
  end

  def self.check!(asset, version:, expected:)
    JrcContactCenter::ConfigurationRevision.check_token!(token(asset, version: version), expected)
  end
end
