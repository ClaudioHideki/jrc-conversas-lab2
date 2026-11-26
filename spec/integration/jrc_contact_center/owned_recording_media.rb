# frozen_string_literal: true

# A declared provider-only test boundary: HTTP authentication, current native scopes, PostgreSQL, audits and player remain real.
# Installed solely by the alternate owned Chrome Rack entry; never required by application initialization.
module SyntheticRecordedCallMedia
  MARKER = 'jrc_cc_owned_recordings_fixture'

  def self.validate_environment!
    config = ApplicationRecord.connection_db_config
    owned = [Rails.env.test?, ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted',
             ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116',
             config.database == 'jrc_sd_bc_portal_concurrency_20261025_test', config.configuration_hash[:host] == '127.0.0.1',
             ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15', ENV.fetch('GITHUB_SHA', '').match?(/\A[0-9a-f]{40}\z/)].all?
    raise 'Owned recording media boundary required' unless owned
  end

  def self.install!
    validate_environment!
    Pabx::Provider.singleton_class.prepend(Factory)
  end

  def self.control!(account)
    validate_environment!
    marker = account.settings.fetch(MARKER)
    valid = valid_marker?(marker)
    valid &&= account.name.start_with?('SYNTHETIC pause ') && account.name.end_with?('-recordings')
    valid &&= valid_nonce?(marker['nonce']) && valid_ids?(marker['record_ids'])
    raise 'Exact owned recording fixture source required' unless valid

    marker
  end

  def self.valid_marker?(marker)
    marker.is_a?(Hash) && marker.keys.sort == %w[nonce record_ids source_sha] && marker['source_sha'] == ENV.fetch('GITHUB_SHA')
  end

  def self.valid_nonce?(nonce)
    nonce.is_a?(String) && nonce.match?(/\A[0-9a-f]{24}\z/)
  end

  def self.valid_ids?(ids)
    ids.is_a?(Array) && ids.length == 24 && ids.uniq.length == 24 && ids.all? { |id| id.is_a?(Integer) && id.positive? }
  end

  def self.wav
    data = "\0".b * 48_000
    "RIFF#{[36 + data.bytesize].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[data.bytesize].pack('V')}#{data}".b
  end

  module Factory
    def new(integration, ...)
      account = integration&.account
      return super unless account&.name&.start_with?('SYNTHETIC pause ') && account.name.end_with?('-recordings')

      Reader.new(account)
    end
  end

  class Reader
    def initialize(account)
      @account = account
      @control = SyntheticRecordedCallMedia.control!(account)
    end

    def recording(record)
      owned = record.account_id == @account.id && @control.fetch('record_ids').include?(record.id) &&
              record.external_unique_id.start_with?("synthetic-recording-#{@control.fetch('nonce')}-")
      raise 'Only exact owned synthetic media may be returned' unless owned

      { body: SyntheticRecordedCallMedia.wav, content_type: 'audio/wav' }
    end
  end
end
