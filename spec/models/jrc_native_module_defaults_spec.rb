require 'rails_helper'

RSpec.describe 'JRC native module availability in a fresh installation' do
  before do
    InstallationConfig.where(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS').delete_all
    ConfigLoader.new.process
  end

  it 'makes Broker and Flows available to a new account without creating operational resources' do
    account = create(:account)

    expect(account.feature_enabled?('jrc_broker')).to be(true)
    expect(account.feature_enabled?('jrc_flows')).to be(true)
    expect(JrcBrokerIntegration.where(account_id: account.id)).not_to exist
    expect(JrcFlowNativeRegistration.where(account_id: account.id)).not_to exist
    expect(JrcFlowNativeBinding.where(account_id: account.id)).not_to exist
  end

  it 'preserves an explicit opt-out on an existing account across configuration reconciliation' do
    account = create(:account)
    account.disable_features!('jrc_broker', 'jrc_flows')

    ConfigLoader.new.process
    account.save!

    expect(account.reload.feature_enabled?('jrc_broker')).to be(false)
    expect(account.feature_enabled?('jrc_flows')).to be(false)
  end

  it 'preserves an existing installation administrator default instead of enabling its accounts silently' do
    defaults = InstallationConfig.find_by!(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    defaults.update!(value: defaults.value.map do |feature|
      %w[jrc_broker jrc_flows].include?(feature['name']) ? feature.merge('enabled' => false) : feature
    end)

    ConfigLoader.new.process
    account = create(:account)

    expect(account.feature_enabled?('jrc_broker')).to be(false)
    expect(account.feature_enabled?('jrc_flows')).to be(false)
  end
end
