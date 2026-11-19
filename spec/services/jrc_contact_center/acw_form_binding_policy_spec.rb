require 'rails_helper'

RSpec.describe JrcContactCenter::AcwFormBindingPolicy do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account) }
  let(:rule) { { 'id' => 'synthetic', 'reason_code' => 'order', 'scope' => 'general', 'scope_id' => nil, 'active' => true, 'limit_seconds' => 180 } }
  # Structural stored-pin fixture only; resolving real owned versions is covered separately.
  let(:reference) do
    { 'rule_id' => 'synthetic', 'form_id' => '9223372036854775807', 'revision' => 1,
      'required_fields' => %w[feedback verified], 'integrity_sha256' => 'a' * 64 }
  end
  let(:legacy_signature) { ['jrc_contact_center_acw', account.id, true, [180, 180]] }

  it 'keeps the exact original policy hash when bindings are absent or explicitly empty' do
    expected = Digest::SHA256.hexdigest(legacy_signature.to_json)
    expect(policy.revision).to eq(expected)
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => { described_class::KEY => [] }))
    expect(policy.revision).to eq(expected)
    expect(service.call).to eq([])
  end

  it 'keeps the original six-field scoped signature when only legacy rules exist' do
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => { 'voice_rules' => [rule] }))
    legacy_fields = %w[id reason_code scope scope_id active limit_seconds]
    expected = legacy_signature + [[legacy_fields.map { |field| rule.fetch(field) }]]
    expect(policy.revision).to eq(Digest::SHA256.hexdigest(expected.to_json))
    expect(rule.keys.sort).to eq(JrcContactCenter::AcwRulePrecedence::FIELDS.sort)
  end

  it 'signs exact form versions and requirements independently of JSON key order without mutating the legacy vector' do
    stored = { 'voice_rules' => [rule], described_class::KEY => [reference] }
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => stored))
    previous = legacy_signature.deep_dup
    first = policy.revision
    expect(service.signature(legacy_signature)).not_to eq(legacy_signature)
    expect(legacy_signature).to eq(previous)
    stored[described_class::KEY] = [reference.to_a.reverse.to_h]
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => stored))
    expect(policy.revision).to eq(first)
    expect(service.call.sole.fetch('form_id')).to eq('9223372036854775807')
  end

  [nil, false, {}, 'bindings'].each do |value|
    it "rejects a present malformed policy field #{value.inspect} rather than dropping it as absent" do
      account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => { described_class::KEY => value }))
      expect { policy.revision }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    end
  end

  it 'does not orphan an existing binding when the associated rule is removed without clearing the link' do
    stored = { 'voice_rules' => [rule], described_class::KEY => [reference] }
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => stored))
    expect do
      service.propose(settings: stored.merge('voice_rules' => []), bindings: :unchanged, rules: [])
    end.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_form_bindings')
    expect(account.reload.settings.fetch(JrcContactCenter::AcwPolicy::KEY)).to eq(stored)
    expect(service.propose(settings: stored.merge('voice_rules' => []), bindings: [], rules: [])).to eq('voice_rules' => [])
  end
end
