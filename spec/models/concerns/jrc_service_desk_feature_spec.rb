# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JRC Service Desk feature registration', type: :model do
  let(:baseline) do
    JSON.parse(Rails.root.join('spec/fixtures/jrc_service_desk/checkpoint1_feature_baseline.json').read)
  end
  let(:feature_list) { YAML.safe_load(Rails.root.join('config/features.yml').read) }
  let(:mapping) { Featurable.feature_flag_mappings_for(feature_list) }

  it 'preserves every previous feature definition in the same order' do
    expect(feature_list.take(baseline.fetch('features').size)).to eq(baseline.fetch('features'))
  end

  it 'preserves every previous column and bit position' do
    baseline.fetch('mappings').each do |name, entry|
      expect(mapping.fetch(entry.fetch('column')).fetch(entry.fetch('position'))).to eq("feature_#{name}".to_sym)
    end
  end

  it 'registers Service Desk in extension position 9, disabled by default' do
    feature = feature_list.find { |entry| entry['name'] == 'jrc_service_desk' }
    expect(feature.fetch('enabled')).to be(false)
    expect(feature.fetch('column')).to eq('feature_flags_ext_1')
    expect(mapping.fetch('feature_flags_ext_1').fetch(9)).to eq(:feature_jrc_service_desk)
  end

  it 'leaves the full primary column at 63 flags' do
    expect(mapping.fetch('feature_flags').size).to eq(63)
  end

  it 'keeps the new flag off for pre-existing bitsets' do
    account = Account.new(feature_flags: (2**63) - 1, feature_flags_ext_1: 255)
    expect(account.feature_enabled?('jrc_service_desk')).to be(false)
  end

  it 'toggles only the new bit, without saving or changing previous flags' do
    account = Account.new(feature_flags: (2**63) - 1, feature_flags_ext_1: 255)
    before = account.all_features.except('jrc_service_desk')
    account.enable_features('jrc_service_desk')
    expect(account.feature_flags).to eq((2**63) - 1)
    expect(account.feature_flags_ext_1).to eq(511)
    expect(account.all_features.except('jrc_service_desk')).to eq(before)
    account.disable_features('jrc_service_desk')
    expect(account.feature_flags_ext_1).to eq(255)
    expect(account.all_features.except('jrc_service_desk')).to eq(before)
  end
end
