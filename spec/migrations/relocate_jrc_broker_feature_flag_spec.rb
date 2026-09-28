require 'rails_helper'
require Rails.root.join('db/migrate/20260925185900_relocate_jrc_broker_feature_flag').to_s

RSpec.describe RelocateJrcBrokerFeatureFlag, type: :model do
  let(:migration) { described_class.new }

  it 'preserves every combination of prior flags and round-trips the Broker entitlement' do
    # All lower bits, Flows, and a high unrelated bit, with Broker both on and off.
    accounts = (0...1024).map do |flags|
      account = create(:account)
      account.update_columns(feature_flags: 123, feature_flags_ext_1: flags | (1 << 40))
      [account, flags | (1 << 40)]
    end

    migration.up
    accounts.each do |account, before|
      account.reload
      expected = (before & ~256) | ((before & 256).zero? ? 0 : 1024)
      expect(account.feature_flags_ext_1).to eq(expected)
      expect(account.feature_flags).to eq(123)
      expect(account.feature_enabled?('jrc_broker')).to eq((before & 256).positive?)
      expect(account.feature_enabled?('jrc_service_desk')).to be(false)
      expect(account.feature_enabled?('jrc_flows')).to eq((before & 512).positive?)
    end

    migration.down
    accounts.each { |account, before| expect(account.reload.feature_flags_ext_1).to eq(before) }
  end

  it 'refuses an occupied destination on upgrade without changing accounts' do
    account = create(:account)
    account.update_column(:feature_flags_ext_1, 1280)
    expect { migration.up }.to raise_error(ActiveRecord::IrreversibleMigration, /1024/)
    expect(account.reload.feature_flags_ext_1).to eq(1280)
  end

  it 'refuses rollback after Service Desk was explicitly enabled' do
    account = create(:account)
    account.update_column(:feature_flags_ext_1, 2047)
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration, /256/)
    expect(account.reload.feature_flags_ext_1).to eq(2047)
  end

  it 'keeps the consolidated feature positions and disabled defaults' do
    flags = Featurable::FEATURES_BY_COLUMN.fetch('feature_flags_ext_1')
    expect(flags.slice(9, 10, 11)).to eq(9 => :feature_jrc_service_desk, 10 => :feature_jrc_flows, 11 => :feature_jrc_broker)
    %w[jrc_service_desk jrc_broker jrc_flows].each do |name|
      expect(Featurable::FEATURE_LIST.find { |flag| flag['name'] == name }.fetch('enabled')).to be(false)
    end
  end
end
