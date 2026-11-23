require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::SourceAuthority do
  include_context 'with native ending execution original evidence'

  subject(:authorization) { described_class.new(account: account, member: member) }

  it 'authorizes the original actor through current native module, queue, call and corporate scopes' do
    expect(authorization.call(origin).id).to eq(source_call.id)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a different current member instead of treating a historical origin as a grant' do
    original = origin
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    wrong = account.account_users.find_by!(user: other)
    expect { described_class.new(account: account, member: wrong).call(original) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks current custom role restrictions after the source was captured' do
    original = origin
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    member.update!(custom_role: role)
    expect { authorization.call(original) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks current eligibility without granting access from the original administrator role' do
    original = origin
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    expect { authorization.call(original) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rechecks the module feature instead of executing under a previously enabled account' do
    original = origin
    account.disable_features!('jrc_contact_center')
    expect { authorization.call(original) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'blocks the inactive original queue while preserving its historical source evidence' do
    original = origin
    queue.update!(status: 'inactive')
    expect { authorization.call(original) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_source_scope_changed')
    expect(original.reload.queue_id).to eq(queue.id)
  end

  it 'blocks the inactive original unit without altering the immutable original mapping' do
    original = origin
    unit.update!(status: 'inactive')
    expect { authorization.call(original) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_source_scope_changed')
    expect(original.reload.unit_id).to eq(unit.id)
  end

  it 'rechecks native queue membership after an administrator becomes an ordinary agent' do
    original = origin
    member.update!(role: :agent)
    expect { authorization.call(original) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a changed live leg actor instead of impersonating its new assignee' do
    original = origin
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    source_leg.update!(account_user: account.account_users.find_by!(user: other))
    expect { authorization.call(original) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(original.reload.actor_user_id).to eq(actor.id)
  end

  it 'never uses a supplied account to authorize an origin belonging to another account' do
    original = origin
    other = create(:account)
    expect { described_class.new(account: other, member: member).call(original) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'allows a current native business-unit grant covering the attested source without requiring global configuration access' do
    original = origin
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: business, active: true, structure_managed: true)
    expect(authorization.call(original).id).to eq(source_call.id)
  end

  it 'blocks a current business-unit grant outside the attested source even for an administrator' do
    original = origin
    other = JrcCrm::BusinessUnit.create!(account: account, operating_company: issuer, name: 'SYNTHETIC other', code: 'SYNTHETIC_OTHER')
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |row| row.update!(active: false) }
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: issuer,
                                     business_unit: other, active: true, structure_managed: true)
    expect { authorization.call(original) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not reinterpret a pending original source after its operational mapping changes' do
    original = origin
    first_scope = original.queue_scope_version_id
    unit.update!(settings: { 'issuer_company_id' => issuer.id })
    expect { authorization.call(original) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_source_scope_changed')
    expect(original.reload.queue_scope_version_id).to eq(first_scope)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
