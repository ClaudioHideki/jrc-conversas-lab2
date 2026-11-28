# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_source')
require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_evidence')

RSpec.describe SyntheticRecordedCallQuality do
  it 'refuses installation outside the owned native recording server without modifying the provider client' do
    before = JrcVoiceQuality::SupabaseClient.ancestors
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.install! }.to raise_error(RuntimeError, /Owned recording media boundary/)
    end
    expect(JrcVoiceQuality::SupabaseClient.ancestors).to eq(before)
  end

  it 'refuses an analysis before reading any account or inventing a provider value outside the owned environment' do
    expect(Account).not_to receive(:find)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.analysis(1, 'not-owned') }.to raise_error(RuntimeError, /Owned recording media boundary/)
    end
  end

  it 'refuses SQL evidence outside the same exact owned environment without creating a correction' do
    expect(JrcContactCenter::QualityReviewRevision).not_to receive(:create!)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { JrcContactCenter::SyntheticQualityReviewEvidence.read(1, 1) }.to raise_error(RuntimeError, /Owned recording media boundary/)
    end
  end

  it 'requires an unchanged original and a contiguous native revision sequence rather than trusting positive counters' do
    original = { 'resumo_conversa' => 'SYNTHETIC original', 'payload_completo' => {}, 'id' => 'synthetic',
                 'call_id' => 'call', 'chamada_id' => 'source' }
    snapshot = JrcContactCenter::QualityAnalysisSnapshot.new(analysis: original, authorized_call_id: 'call')
    row = instance_double(
      JrcContactCenter::QualityReviewRevision,
      revision: 2, original_analysis: JrcContactCenter::QualityReviewPresentation.original(snapshot), source_sha256: snapshot.sha256
    )
    expect { JrcContactCenter::SyntheticQualityReviewEvidence.require_original!([row], snapshot) }.to raise_error(RuntimeError, /revision sequence/)
  end

  it 'refuses the new aggregate provider boundary outside the same owned environment before reading native accounts' do
    expect(Account).not_to receive(:find)
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect do
        described_class.metrics(account_id: 1, call_ids: ['SYNTHETIC-not-owned'], observed_before: Time.current)
      end.to raise_error(RuntimeError, /Owned recording media boundary/)
    end
  end

  it 'preserves the metric reader class when installation is refused outside the alternate owned server' do
    before = JrcVoiceQuality::AnalysisMetricReader.ancestors
    with_modified_env(GITHUB_ACTIONS: 'false') do
      expect { described_class.install! }.to raise_error(RuntimeError, /Owned recording media boundary/)
    end
    expect(JrcVoiceQuality::AnalysisMetricReader.ancestors).to eq(before)
  end
end
