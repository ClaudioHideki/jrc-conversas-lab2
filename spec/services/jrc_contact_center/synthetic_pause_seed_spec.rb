require 'rails_helper'
require Rails.root.join('script/jrc_call_center_pause_seed')

RSpec.describe JrcContactCenter::SyntheticPauseSeed do
  it 'rejects provisioning outside the exclusive synthetic runner without writing an Account' do
    before = Account.count
    with_modified_env(GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted') do
      expect { described_class.call(projects: ['not-authorized']) }.to raise_error(RuntimeError, 'Owned synthetic pause runner required')
    end
    expect(Account.count).to eq(before)
  end

  it 'does not expose a constructor that bypasses resource guards' do
    expect { described_class.new('not-authorized') }.to raise_error(NoMethodError)
  end
end
