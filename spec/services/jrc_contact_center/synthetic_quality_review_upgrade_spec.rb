# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('script/jrc_call_center_quality_review_upgrade')
require Rails.root.join('script/jrc_call_center_quality_schema_probe')

RSpec.describe JrcContactCenter::SyntheticQualityReviewUpgrade do
  it 'refuses preparation before any write outside the exact owned disposable GitHub database' do
    expect(Account).not_to receive(:create!)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.new.prepare }.to raise_error(RuntimeError, /Exclusive committed quality review/)
    end
  end

  it 'refuses verification outside the same environment instead of loading a previous fixture or running a migration' do
    expect(File).not_to receive(:read).with(described_class::BEFORE)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.new.verify }.to raise_error(RuntimeError, /Exclusive committed quality review/)
    end
  end

  it 'uses separate owned output paths and a separate upgrade database without replacing earlier typed evidence' do
    expect(described_class::BEFORE).not_to eq(JrcContactCenter::SyntheticTypedDestinationUpgrade::BEFORE)
    expect(described_class::AFTER).not_to eq(JrcContactCenter::SyntheticTypedDestinationUpgrade::AFTER)
    expect(described_class::DATABASE).not_to eq(JrcContactCenter::SyntheticTypedDestinationUpgrade::DATABASE)
  end

  it 'rejects a schema proof in a non-owned process without writing a fake diagnostic receipt' do
    expect(File).not_to receive(:write)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { JrcContactCenter::SyntheticQualitySchemaProbe.record('fresh') }.to raise_error(RuntimeError, /Exclusive disposable quality/)
    end
  end
end
