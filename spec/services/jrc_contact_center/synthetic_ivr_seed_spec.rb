require 'rails_helper'
require Rails.root.join('script/jrc_call_center_ivr_seed')

RSpec.describe JrcContactCenter::SyntheticIvrSeed do
  it 'does not provision accounts outside the explicitly owned disposable runner' do
    before = Account.count
    with_modified_env(GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted') do
      expect { described_class.call(projects: ['not-authorized']) }.to raise_error(RuntimeError, 'Owned synthetic IVR runner required')
    end
    expect(Account.count).to eq(before)
  end

  it 'does not expose a constructor that bypasses the owned-runner entry point' do
    expect { described_class.new('not-authorized') }.to raise_error(NoMethodError)
  end
end
