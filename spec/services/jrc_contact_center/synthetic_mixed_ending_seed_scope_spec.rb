# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_mixed_ending_seed')
require Rails.root.join('spec/integration/jrc_contact_center/owned_mixed_ending_evidence')

RSpec.describe JrcContactCenter::SyntheticMixedEndingSeed do
  it 'refuses preparation before creating records or modifying an account outside the exact owned runner' do
    before = [Account.count, JrcCrm::Lead.count, JrcServiceDesk::Ticket.count, JrcContactCenter::CallSession.count]
    with_modified_env(GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted') do
      expect { described_class.call(account: nil) }
        .to raise_error(RuntimeError, 'Owned disposable public ending environment required')
    end
    expect([Account.count, JrcCrm::Lead.count, JrcServiceDesk::Ticket.count, JrcContactCenter::CallSession.count]).to eq(before)
  end

  it 'cannot remove a failure constraint or inspect business records outside that isolated runner' do
    expect(ApplicationRecord.connection).not_to receive(:remove_check_constraint)
    with_modified_env(GITHUB_ACTIONS: 'false', RUNNER_ENVIRONMENT: 'github-hosted') do
      expect { SyntheticMixedEndingEvidence.allow_selected_retry!(1) }
        .to raise_error(RuntimeError, 'Owned disposable public ending environment required')
      expect { SyntheticMixedEndingEvidence.read(1) }
        .to raise_error(RuntimeError, 'Owned disposable public ending environment required')
    end
  end
end
