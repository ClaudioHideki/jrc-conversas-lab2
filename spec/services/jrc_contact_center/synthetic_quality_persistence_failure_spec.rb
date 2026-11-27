# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_persistence_failure')

RSpec.describe JrcContactCenter::SyntheticQualityPersistenceFailure, :pabx do
  %w[enable disable].each do |action|
    it "rejects #{action} outside the exact hosted Chrome environment before consulting any account" do
      expect(Account).not_to receive(:find)
      with_modified_env(GITHUB_ACTIONS: 'false') do
        expect { described_class.call(action, 1, 1) }.to raise_error(RuntimeError, 'Owned recording media boundary required')
      end
    end
  end
end
