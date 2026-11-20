require 'rails_helper'

RSpec.describe JrcContactCenter::AcwEndingReasons do
  let(:account) { create(:account) }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account) }
  let(:catalog) { described_class.new(account: account) }
  let(:entry) do
    { 'code' => 'synthetic', 'name' => 'SYNTHETIC reason', 'category' => 'SYNTHETIC', 'description' => '', 'order' => 0, 'active' => true }
  end

  it 'preserves the exact legacy empty policy revision when no catalogue was configured' do
    expected = Digest::SHA256.hexdigest([JrcContactCenter::AcwPolicy::KEY, account.id, true, [180, 180]].to_json)
    expect(policy.revision).to eq(expected)
    expect(catalog.call).to eq('version' => 0, 'entries' => [])
  end

  [nil, false, {}, { 'version' => 1, 'entries' => false }].each do |invalid|
    it "fails closed for malformed stored configuration #{invalid.inspect}" do
      account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => { described_class::KEY => invalid }))
      expect { catalog.call }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_ending_reasons')
      expect { policy.revision }.to raise_error(JrcContactCenter::OperationError, 'invalid_acw_ending_reasons')
    end
  end

  it 'returns a defensive copy without permitting a caller to mutate stored historical versions' do
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], expected_revision: policy.revision)
    original = catalog.call
    original['entries'].first['name'] = 'changed only in caller'
    expect(catalog.call.fetch('entries').sole.fetch('name')).to eq(entry.fetch('name'))
  end

  it 'rolls back the full policy mutation when its mandatory audit cannot be written' do
    before = account.settings.deep_dup
    allow(JrcContactCenter::AcwPolicyAudit).to receive(:write!).and_raise(ActiveRecord::RecordInvalid)
    expect do
      policy.update!({ voice: 300, whatsapp: 300 }, voice_reason_catalog: [entry], expected_revision: policy.revision)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.reload.settings).to eq(before)
  end

  it 'preserves all existing scoped rule fields and hashes while adding an administrative catalogue' do
    rule = { 'id' => 'synthetic', 'reason_code' => 'order', 'scope' => 'general', 'scope_id' => nil, 'active' => true, 'limit_seconds' => 120 }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: [rule], expected_revision: policy.revision)
    before = JrcContactCenter::AcwScopedRules.new(account: account).call
    hash = Digest::SHA256.hexdigest(before.to_json)
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], expected_revision: policy.revision)
    expect(JrcContactCenter::AcwScopedRules.new(account: account).call).to eq(before)
    expect(Digest::SHA256.hexdigest(JrcContactCenter::AcwScopedRules.new(account: account).call.to_json)).to eq(hash)
    expect(JrcContactCenter::Qualification.where(account: account)).to be_empty
  end

  it 'keeps the revision stable across a real PostgreSQL JSONB reload and object-key reordering' do
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], expected_revision: policy.revision)
    persisted = policy.revision
    account.reload
    expect(policy.revision).to eq(persisted)
    state = catalog.call
    reversed = state.merge('entries' => state.fetch('entries').map { |row| row.to_a.reverse.to_h }).to_a.reverse.to_h
    account.update!(settings: account.settings.deep_merge(JrcContactCenter::AcwPolicy::KEY => { described_class::KEY => reversed }))
    expect(policy.revision).to eq(persisted)
  end


  it 'filters the complete new request catalogue while leaving the existing account identity available to logs' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter('voice_reason_catalog' => [entry], 'account_id' => account.id.to_s)
    expect(filtered.fetch('voice_reason_catalog')).to eq('[FILTERED]')
    expect(filtered.fetch('account_id')).to eq(account.id.to_s)
    expect(filtered.to_json).not_to include(entry.fetch('name'))
  end

  context 'with an already captured native voice qualification' do
    include_context 'with an owned immutable operational ACW form'

    it 'leaves the entire qualification, rule snapshot, exact form version and private answers unchanged' do
      previous_record = record.attributes.deep_dup
      form_state = JrcContactCenter::QualificationForm.find_by!(qualification: record)
      previous_form = form_state.attributes.deep_dup
      previous_origin = JrcContactCenter::AcwQualificationPolicy.new(record).snapshot
      policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], expected_revision: policy.revision)
      expect(record.reload.attributes).to eq(previous_record)
      expect(form_state.reload.attributes).to eq(previous_form)
      expect(JrcContactCenter::AcwQualificationPolicy.new(record).snapshot).to eq(previous_origin)
    end
  end

end
