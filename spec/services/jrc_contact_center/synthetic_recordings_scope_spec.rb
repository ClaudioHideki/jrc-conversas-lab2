# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_recordings_seed')
require Rails.root.join('spec/integration/jrc_contact_center/owned_recording_media')

RSpec.describe JrcContactCenter::SyntheticRecordingsSeed do
  it 'rejects seeding before changing accounts, calls, SIP or native integration settings outside the explicit runner' do
    before = [Account.count, JrcContactCenter::CallSession.count, SipCredential.count, TelephonyIntegration.count]
    with_modified_env(GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted') do
      expect do
        JrcContactCenter::SyntheticRecordingsSeed.call(account: nil, operator: nil, viewer: nil, queues: [])
      end.to raise_error(RuntimeError, 'Owned synthetic recording scope required')
    end
    expect([Account.count, JrcContactCenter::CallSession.count, SipCredential.count, TelephonyIntegration.count]).to eq(before)
  end

  it 'cannot install the provider-only byte boundary outside the exclusive runner' do
    before = Pabx::Provider.singleton_class.ancestors
    with_modified_env(GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted') do
      expect { SyntheticRecordedCallMedia.install! }.to raise_error(RuntimeError, 'Owned recording media boundary required')
    end
    expect(Pabx::Provider.singleton_class.ancestors).to eq(before)
  end
end
