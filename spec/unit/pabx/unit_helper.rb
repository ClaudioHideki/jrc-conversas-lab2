# These are project-gem unit tests, not a replacement for Rails request/database tests.
require 'rails'
require 'active_support/all'
require 'active_record'
require 'webmock/rspec'
require 'climate_control'
require_relative '../../spec_helper'

WebMock.disable_net_connect!
Time.zone = 'America/Sao_Paulo'
unless Rails.application
  ActiveRecord::Encryption.configure(primary_key: SecureRandom.hex(32), deterministic_key: SecureRandom.hex(32),
                                    key_derivation_salt: SecureRandom.hex(32))
end

module Pabx
end
%w[error settings contract client provider diagnostics].each do |file|
  require File.expand_path("../../../app/services/pabx/#{file}", __dir__)
end

RSpec.shared_context 'PABX configuration unit' do
  let(:configuration) do
    { 'provider' => 'pabx_v1', 'enabled' => false, 'base_url' => 'https://pbx.example.test',
      'expected_tenant' => '8', 'test_extension' => '1410', 'technical_identity' => 'tenant_prefix' }
  end
  let(:integration) do
    double('configuration without persistence', id: 101, account_id: 11, pabx_settings: configuration, pabx_sync_state: {},
           pabx_username: 'synthetic@example.test', pabx_password: 'synthetic-api-password', account: account)
  end
  let(:account) { double('current account') }
  before { allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new) }
end
