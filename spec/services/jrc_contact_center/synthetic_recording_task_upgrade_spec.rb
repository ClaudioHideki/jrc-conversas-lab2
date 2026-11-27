# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_recording_task_upgrade')

RSpec.describe JrcContactCenter::SyntheticRecordingTaskUpgrade do
  it 'refuses preparation before any write outside its exact owned disposable upgrade database' do
    expect(Account).not_to receive(:create!)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.new.prepare }.to raise_error(RuntimeError, /Exclusive committed recording task/)
    end
  end

  it 'refuses verification outside the same environment before reading any baseline or executing a migration' do
    expect(File).not_to receive(:read).with(described_class::BEFORE)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.new.verify }.to raise_error(RuntimeError, /Exclusive committed recording task/)
    end
  end

  it 'preserves the existing typed and human-review output paths and databases' do
    previous = JrcContactCenter::SyntheticTypedDestinationUpgrade
    expect(described_class::BEFORE).not_to eq(previous::BEFORE)
    expect(described_class::AFTER).not_to eq(previous::AFTER)
    expect(described_class::DATABASE).not_to eq(previous::DATABASE)
    expect(described_class::HISTORY).to eq('jrc_contact_center_recording_task_links')
  end
end
