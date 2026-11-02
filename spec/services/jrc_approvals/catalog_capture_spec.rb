require 'rails_helper'

RSpec.describe JrcApprovals::Catalog, :approval_core do
  let(:scope) { approval_scope }
  let(:actor) { approval_actor(scope) }
  let(:base) { described_class.fetch('synthetic.review') }
  let(:key) { 'synthetic.capture_regression' }

  after do
    described_class.instance_variable_get(:@mutex).synchronize do
      described_class.instance_variable_get(:@entries).delete(key)
    end
  end

  it 'preserves existing callable objects that expose call without exposing Proc arity' do
    capture = Object.new
    original = base.capture
    capture.define_singleton_method(:call) { |record| original.call(record) }
    described_class.register(key: key, version: 1, model: base.model, fields: base.fields, authorize: base.authorize, capture: capture)
    actual = described_class.snapshot(account: scope[:account], user: actor.user, key: key, resource_id: scope[:unit].id)
    expected = described_class.snapshot(account: scope[:account], user: actor.user, key: 'synthetic.review', resource_id: scope[:unit].id)
    expect(actual['values']).to eq(expected['values'])
  end

  it 'passes the actual authenticated actor to explicitly actor-aware server captures' do
    original = base.capture
    capture = lambda do |record, user|
      original.call(record).deep_merge(values: { count: user.id })
    end
    described_class.register(key: key, version: 1, model: base.model, fields: base.fields, authorize: base.authorize, capture: capture)
    actual = described_class.snapshot(account: scope[:account], user: actor.user, key: key, resource_id: scope[:unit].id)
    expect(actual.dig('values', 'count')).to eq(actor.user_id)
  end

  it 'runs physical verification only explicitly and never before tenant-scoped resource authorization' do
    calls = []
    described_class.register(key: key, version: 1, model: base.model, fields: base.fields, authorize: base.authorize, capture: base.capture,
                             verify: lambda { |record, user|
                               calls << [record.id, user.id]
                               true
                             })
    described_class.snapshot(account: scope[:account], user: actor.user, key: key, resource_id: scope[:unit].id)
    expect(calls).to be_empty
    described_class.verify!(account: scope[:account], user: actor.user, key: key, resource_id: scope[:unit].id)
    expect(calls).to eq([[scope[:unit].id, actor.user_id]])
    foreign = approval_scope
    expect do
      described_class.verify!(account: foreign[:account], user: actor.user, key: key, resource_id: scope[:unit].id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(calls.length).to eq(1)
  end

  it 'fails closed when a registered physical verifier does not affirm successful verification' do
    described_class.register(key: key, version: 1, model: base.model, fields: base.fields, authorize: base.authorize, capture: base.capture,
                             verify: ->(*) { false })
    expect do
      described_class.verify!(account: scope[:account], user: actor.user, key: key, resource_id: scope[:unit].id)
    end.to raise_error(JrcApprovals::Error, 'EVIDENCE_UNVERIFIED')
  end
end
