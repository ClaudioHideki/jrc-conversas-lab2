require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActionQueueScope, 'scope history' do
  include_context 'with a native ending action queue scope'

  it 'records a new identity on corporate A-to-B-to-A transitions instead of reviving an old authorization' do
    original = scope.attributes.deep_dup
    unit.update!(settings: { 'issuer_company_id' => issuer.id })
    unit.update!(settings: { 'issuer_company_id' => issuer.id, 'business_unit_id' => business.id })
    rows = scopes.reload.to_a
    expect(rows.map(&:revision)).to eq([1, 2, 3])
    expect(rows.map(&:id).uniq.length).to eq(3)
    expect(rows.last.scope_digest).to eq(original.fetch('scope_digest'))
    expect(rows.first.attributes).to eq(original)
    expect(rows.map(&:created_at)).to eq(rows.map(&:created_at).sort.uniq)
  end

  it 'records queue retargeting independently from a matching corporate mapping' do
    scope
    other = JrcContactCenter::Unit.create!(account: account, code: 'OTHER', name: 'SYNTHETIC second unit', kind: 'sac', settings: unit.settings)
    queue.update!(unit: other)
    queue.update!(unit: unit)
    expect(scopes.pluck(:unit_id)).to eq([unit.id, other.id, unit.id])
    expect(scopes.pluck(:revision)).to eq([1, 2, 3])
  end

  it 'records issuer deactivation and reactivation even when the operational settings do not change' do
    scope
    issuer.update!(active: false)
    issuer.update!(active: true)
    expect(scopes.pluck(:scope_state)).to eq(%w[mapped invalid mapped])
    expect(scopes.pluck(:revision)).to eq([1, 2, 3])
    expect(scopes.last.scope_digest).to eq(scope.scope_digest)
  end

  it 'records business-unit deactivation and reactivation without changing operational settings' do
    scope
    business.update!(active: false)
    business.update!(active: true)
    expect(scopes.pluck(:scope_state)).to eq(%w[mapped invalid mapped])
    expect(scopes.pluck(:revision)).to eq([1, 2, 3])
  end

  it 'records a business-unit issuer changed through SQL instead of treating bypassed model validation as an old valid binding' do
    scope
    other = JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC other issuer', relationship_type: 'internal', active: true)
    guarded_ending_scope_sql("UPDATE jrc_crm_business_units SET company_id=#{other.id} WHERE id=#{business.id}")
    guarded_ending_scope_sql("UPDATE jrc_crm_business_units SET company_id=#{issuer.id} WHERE id=#{business.id}")
    expect(scopes.pluck(:scope_state)).to eq(%w[mapped invalid mapped])
    expect(scopes.pluck(:revision)).to eq([1, 2, 3])
  end

  it 'rejects foreign corporate identities without disrupting the existing native queue' do
    other_account = create(:account)
    other = JrcCustomers::Company.create!(account: other_account, name: 'SYNTHETIC foreign issuer', relationship_type: 'internal', active: true)
    scope
    write_ending_scope_settings('issuer_company_id' => other.id)
    current = scopes.last
    expect(current.scope_state).to eq('invalid')
    expect([current.issuer_company_id, current.business_unit_id]).to eq([nil, nil])
    expect(queue.reload.unit_id).to eq(unit.id)
    expect(scopes.where(account: other_account)).to be_empty
  end

  [false, [], '', { 'issuer_company_id' => false, 'business_unit_id' => '1' }, { 'issuer_company_id' => 1.5 }].each do |malformed|
    it "records malformed legacy mapping #{malformed.inspect} as unavailable instead of coercing it into a grant" do
      scope
      write_ending_scope_settings(malformed)
      expect(scopes.last.scope_state).to eq('invalid')
      expect([scopes.last.issuer_company_id, scopes.last.business_unit_id]).to eq([nil, nil])
      expect(queue.reload.unit_id).to eq(unit.id)
    end
  end

  it 'keeps ledger rows and current capture queries separated by the native account' do
    scope
    other_account = create(:account)
    other_unit = JrcContactCenter::Unit.create!(account: other_account, code: 'SYNTHETIC', name: 'SYNTHETIC foreign', kind: 'sac')
    other_queue = JrcContactCenter::Queue.create!(account: other_account, unit: other_unit, code: 'SYNTHETIC', name: 'SYNTHETIC foreign',
                                                  service_kind: 'voice', strategy: 'ring_all')
    other_scope = JrcContactCenter::EndingActionQueueScope.find_by!(account: other_account, source_queue_id: other_queue.id)
    expect(other_scope.scope_state).to eq('unmapped')
    expect(scopes.where(id: other_scope.id)).to be_empty
    expect(JrcContactCenter::EndingActionQueueScope.where(account: other_account, source_queue_id: queue.id)).to be_empty
  end
end
