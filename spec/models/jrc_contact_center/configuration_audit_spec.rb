require 'rails_helper'

RSpec.describe 'Call Center configuration audit transactions', type: :model do
  let(:account) { create(:account) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'AUDIT', name: 'Original', kind: 'sac') }
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::COMMENT) }

  it 'captures only allowed fields and scope when the local record is created' do
    target = JrcContactCenter::Unit.create!(
      account: account, code: 'SAFE', name: 'Safe', kind: 'sac', settings: { 'provider_password' => 'NEVER-IN-AUDIT' }
    )
    audit = audits.find_by!(auditable: target)
    expect(audit.action).to eq('create')
    expected = target.as_json(only: %i[code name kind status timezone parent_unit_id]).merge('settings' => {})
    expect(audit.audited_changes.fetch('attributes')).to eq([nil, expected])
    expect(audit.audited_changes.to_json).not_to include('NEVER-IN-AUDIT')
    expect(audit.audited_changes.dig('cc_scope', 'after', 'account_id')).to eq(account.id.to_s)
    expect(audit.request_uuid).to be_present
  end

  it 'records an omitted settings change without copying its previous or current content' do
    unit.update!(settings: { 'provider_password' => 'OLD-PRIVATE-VALUE' })
    previous = audits.where(auditable: unit).count
    unit.update!(settings: { 'provider_password' => 'NEW-PRIVATE-VALUE' })
    expect(audits.where(auditable: unit).count).to eq(previous + 1)
    body = audits.where(auditable: unit).order(:id).last.audited_changes
    expect(body.fetch('omitted_fields')).to include('settings')
    expect(body.to_json).not_to include('OLD-PRIVATE-VALUE', 'NEW-PRIVATE-VALUE')
  end

  it 'does not create an artificial update event for an unchanged record' do
    unit
    expect { unit.update!(name: unit.name) }.not_to change { audits.where(auditable: unit).count }
  end

  it 'rolls back the mutation and its success audit together' do
    unit
    count = audits.count
    JrcContactCenter::Unit.transaction do
      unit.update!(name: 'Must roll back')
      raise ActiveRecord::Rollback
    end
    expect(unit.reload.name).to eq('Original')
    expect(audits.count).to eq(count)
  end

  it 'keeps participation and supervision as independent audited flags' do
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q', name: 'Queue')
    user = create(:user, account: account)
    member = account.account_users.find_by!(user: user)
    link = JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member, role: 'agent')
    link.update!(settings: { 'supervises' => true, 'private' => 'OMIT-THIS' })
    before, after = audits.where(auditable: link).order(:id).last.audited_changes.fetch('attributes')
    expect(before).to include('participates' => true, 'supervises' => false)
    expect(after).to include('participates' => true, 'supervises' => true)
    expect(after.to_json).not_to include('OMIT-THIS')
  end

  it 'does not persist a success audit for a validation failure' do
    unit
    count = audits.count
    expect { unit.update!(kind: 'invalid') }.to raise_error(ActiveRecord::RecordInvalid)
    expect(unit.reload.kind).to eq('sac')
    expect(audits.count).to eq(count)
  end

  it 'rolls back a deletion audit when dependent local records block the removal' do
    JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'BLOCKED', name: 'Dependent')
    count = audits.count
    expect { unit.destroy! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(unit.reload).to be_persisted
    expect(audits.count).to eq(count)
  end

  it 'retains the sanitized snapshot when a local configuration is removed' do
    unit
    id = unit.id
    unit.destroy!
    audit = audits.find_by!(auditable_type: 'JrcContactCenter::Unit', auditable_id: id, action: 'destroy')
    expect(audit.audited_changes.fetch('attributes').first).to include('name' => 'Original')
    expect(audit.audited_changes.fetch('attributes').last).to be_nil
    expect(audit.audited_changes.dig('cc_scope', 'before', 'unit_id')).to eq(id.to_s)
  end

  it 'preserves an ordered version trail for successive actual changes' do
    unit.update!(name: 'First reviewed name')
    unit.update!(name: 'Second reviewed name')
    trail = audits.where(auditable: unit).order(:id)
    expect(trail.pluck(:version)).to eq([1, 2, 3])
    expect(trail.last.audited_changes.fetch('attributes')).to include(a_hash_including('name' => 'First reviewed name'))
    expect(trail.last.audited_changes.fetch('attributes').last).to include('name' => 'Second reviewed name')
  end
end
