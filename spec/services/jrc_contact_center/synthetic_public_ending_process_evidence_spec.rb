# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/integration/jrc_contact_center/owned_public_ending_process_evidence')

RSpec.describe SyntheticPublicEndingProcessEvidence do
  let(:common) do
    { 'jid' => 'a' * 24, 'job_class' => 'JrcContactCenter::EndingActionsJob', 'account_id' => 11, 'record_id' => 17,
      'source_sha' => 'b' * 40, 'queue' => 'jrc_cc_public_synthetic' }
  end
  let(:input) { common.merge('producer_pid' => 100, 'parent_job' => nil) }
  let(:output) { common.merge('worker_pid' => 200, 'postgres_backend_pid' => 300) }
  let(:child) do
    common.merge('jid' => 'c' * 24, 'job_class' => 'JrcContactCenter::EndingDestinationJob', 'record_id' => 23,
                 'producer_pid' => 200, 'parent_job' => input.slice(*described_class::IDENTITY))
  end
  let(:child_output) { child.except('producer_pid', 'parent_job').merge('worker_pid' => 200, 'postgres_backend_pid' => 301) }
  let(:produced) { { input.fetch('jid') => input, child.fetch('jid') => child } }
  let(:acks) { { output.fetch('jid') => output, child_output.fetch('jid') => child_output } }

  it 'retains the independent process requirement for the actual HTTP-produced root job' do
    expect(described_class.verify!(input, output, produced: produced, acks: acks, expected_qualification_id: nil)).to be(true)
  end

  it 'rejects a root job executed in the producer process even if all IDs are positive' do
    bad = input.merge('producer_pid' => output.fetch('worker_pid'))
    expect do
      described_class.verify!(bad, output, produced: produced, acks: acks, expected_qualification_id: nil)
    end.to raise_error(RuntimeError, 'Independent HTTP producer and worker required')
  end

  it 'proves a native child in the same worker process only through its actual independent parent and native qualification' do
    expect(described_class.verify!(child, child_output, produced: produced, acks: acks, expected_qualification_id: 17)).to be(true)
  end

  it 'rejects a missing parent receipt rather than treating a matching worker PID as sufficient evidence' do
    expect do
      described_class.verify!(child, child_output, produced: produced.except(input.fetch('jid')), acks: acks, expected_qualification_id: 17)
    end.to raise_error(KeyError)
  end

  it 'rejects another origin, fake producer or a cyclic parent without accepting the child' do
    invalid = [child, child.merge('producer_pid' => 201), child.merge('parent_job' => child.slice(*described_class::IDENTITY))]
    invalid.each_with_index do |row, index|
      expect do
        described_class.verify!(row, child_output, produced: produced, acks: acks, expected_qualification_id: index.zero? ? 99 : 17)
      end.to raise_error(RuntimeError)
    end
  end

  it 'clears the per-job witness on success or failure and restores an earlier frame' do
    previous = Thread.current[described_class::THREAD_KEY]
    described_class.with_job({ 'jid' => common.fetch('jid') }, [11, 17], common.fetch('job_class')) do
      expect(described_class.parent_job).to eq(input.slice(*described_class::IDENTITY))
      expect do
        described_class.with_job({ 'jid' => child.fetch('jid') }, [11, 23], child.fetch('job_class')) { raise 'SYNTHETIC failure' }
      end.to raise_error(RuntimeError, 'SYNTHETIC failure')
      expect(described_class.parent_job).to eq(input.slice(*described_class::IDENTITY))
    end
    expect(Thread.current[described_class::THREAD_KEY]).to equal(previous)
  end
end
