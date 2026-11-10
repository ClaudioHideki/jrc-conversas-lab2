require 'rails_helper'

RSpec.describe JrcFlows::OwnershipEffects do
  self.use_transactional_tests = false # No records are written; completion must observe the real non-transactional path.
  let(:ledger) { double('isolated effect ledger') }
  let(:queries) { [] }
  let(:context) { { scope_key: 'synthetic-effect', generation: 1, execution_id: SecureRandom.uuid, pending: [] } }

  around do |example|
    previous = Thread.current[:jrc_flow_ownership]
    Thread.current[:jrc_flow_ownership] = context
    example.run
  ensure
    Thread.current[:jrc_flow_ownership] = previous
  end

  before do
    allow(JrcFlows::OwnershipGuard).to receive(:checkpoint!)
    allow(JrcFlows::OwnershipLedger).to receive(:transaction_sql).and_yield(ledger)
    allow(ledger).to receive(:select_value).and_return(false)
    allow(ledger).to receive(:execute) { |query| queries << query }
  end

  it 'retains an observed completion without marking a successful effect uncertain' do
    result = described_class.perform(reference: 'synthetic-success', kind: 'EXTERNAL') { :result }
    expect(result).to eq(:result)
    expect(context[:pending].length).to eq(1)
    expect(queries.join).to include("state='OBSERVED'")
    expect(queries.join).not_to include("state='UNKNOWN'", "state='CANCELED'")
  end

  [StandardError, Interrupt, SystemExit].each do |exception_class|
    it "preserves uncertainty and propagates #{exception_class} after dispatch" do
      error = exception_class.new('synthetic interruption')
      expect do
        described_class.perform(reference: 'synthetic-failure', kind: 'EXTERNAL') { raise error }
      end.to raise_error(exception_class) { |caught| expect(caught).to equal(error) }
      expect(queries.join).to include("state='UNKNOWN'")
      expect(context[:pending]).to be_empty
    end
  end

  it 'marks a pre-dispatch checkpoint rejection canceled without invoking the effect' do
    checks = 0
    allow(JrcFlows::OwnershipGuard).to receive(:checkpoint!) do
      checks += 1
      raise 'synthetic revoked checkpoint' if checks == 2
    end
    invoked = false
    expect do
      described_class.perform(reference: 'synthetic-canceled', kind: 'EXTERNAL') { invoked = true }
    end.to raise_error('synthetic revoked checkpoint')
    expect(invoked).to be(false)
    expect(queries.join).to include("state='CANCELED'")
  end
end
