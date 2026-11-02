require 'rails_helper'

RSpec.describe JrcHumanAssignment::Policy, '.update!' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:second_inbox) { create(:inbox, account: account) }

  before { Current.user = admin }
  after { Current.reset }

  it 'records one safe snapshot per impacted inbox with the current administrator and unchanged DTO' do
    conversation = create(:conversation, account: account, inbox: inbox, assignee: admin)
    result = described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id, second_inbox.id])
    expect(result).to eq(enabled: true, max_open: 2, inbox_ids: [inbox.id, second_inbox.id])
    events = JrcHumanAssignmentPolicyEvent.where(account_id: account.id).where.not(inbox_id: nil).order(:id)
    expect(events.pluck(:inbox_id)).to contain_exactly(inbox.id, second_inbox.id)
    expect(events.pluck(:user_id)).to eq([admin.id, admin.id])
    expect(events.first.previous_policy).to eq('scope' => 'GLOBAL', 'enabled' => false, 'included' => false, 'max_open' => 10)
    expect(events.first.next_policy).to eq('scope' => 'GLOBAL', 'enabled' => true, 'included' => true, 'max_open' => 2)
    expect(conversation.reload.assignee_id).to eq(admin.id)
  end

  it 'adds exactly one account-global configuration snapshot alongside impacted inbox events' do
    described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id, second_inbox.id])
    global_events = JrcHumanAssignmentPolicyEvent.where(account_id: account.id, inbox_id: nil)
    expect(global_events.count).to eq(1)
    expect(global_events.first.user_id).to eq(admin.id)
    expect(global_events.first.previous_policy).to eq('scope' => 'GLOBAL_ACCOUNT', 'enabled' => false, 'max_open' => 10, 'inbox_ids' => [])
    expect(global_events.first.next_policy).to eq(
      'scope' => 'GLOBAL_ACCOUNT', 'enabled' => true, 'max_open' => 2, 'inbox_ids' => [inbox.id, second_inbox.id]
    )
  end

  it 'audits both removed and added connections using their own effective state' do
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'enabled' => true, 'max_open' => 2, 'inbox_ids' => [inbox.id] } })
    described_class.update!(account, enabled: true, max_open: 3, inbox_ids: [second_inbox.id])
    events = JrcHumanAssignmentPolicyEvent.where(account_id: account.id).where.not(inbox_id: nil).index_by(&:inbox_id)
    expect(events.keys).to contain_exactly(inbox.id, second_inbox.id)
    expect(events[inbox.id].previous_policy).to include('enabled' => true, 'included' => true)
    expect(events[inbox.id].next_policy).to include('enabled' => false, 'included' => false, 'max_open' => 3)
    expect(events[second_inbox.id].previous_policy).to include('enabled' => false, 'included' => false)
    expect(events[second_inbox.id].next_policy).to include('enabled' => true, 'included' => true)
  end

  it 'preserves local overrides and does not report them as impacted by global changes' do
    team = create(:team, account: account, allow_auto_assign: true)
    options = { enabled: true, mode: 'direct', team_ids: [team.id], max_open: 5 }
    described_class.update_connection!(account, inbox: inbox, actor: admin, **options)
    override = described_class.connection_for(account, inbox.id).deep_dup
    described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id, second_inbox.id])
    expect(described_class.connection_for(account.reload, inbox.id)).to eq(override)
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id).group(:inbox_id).count).to eq(nil => 1, inbox.id => 1, second_inbox.id => 1)
  end

  it 'does not append duplicate audit rows for unchanged configuration' do
    described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    end.not_to change(JrcHumanAssignmentPolicyEvent, :count)
  end

  it 'rolls back the policy and an earlier audit row when a later row fails' do
    first_id = inbox.id
    second_id = second_inbox.id
    before = account.reload.custom_attributes.deep_dup
    created_ids = []
    allow(JrcHumanAssignmentPolicyEvent).to receive(:create!).and_wrap_original do |original, attributes|
      raise ActiveRecord::RecordInvalid if attributes[:inbox_id] == second_id

      row = original.call(attributes)
      created_ids << row.id
      row
    end
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [first_id, second_id])
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(created_ids.size).to eq(1)
    expect(account.reload.custom_attributes).to eq(before)
    expect(JrcHumanAssignmentPolicyEvent.where(id: created_ids)).to be_empty
  end

  it 'rejects a foreign inbox atomically without writing an audit event' do
    foreign_inbox = create(:inbox)
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [foreign_inbox.id])
    end.to raise_error(ArgumentError)
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id)).to be_empty
  end

  it 'rejects a foreign actor instead of attributing another tenant user or System' do
    Current.user = create(:user, account: create(:account), role: :administrator)
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    end.to raise_error(ArgumentError)
    expect(account.reload.custom_attributes['jrc_human_assignment']).to be_nil
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id)).to be_empty
  end

  it 'rechecks revoked administrator membership even when Current.user is stale' do
    account.account_users.find_by!(user_id: admin.id).update!(role: :agent)
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    end.to raise_error(ArgumentError)
  end

  it 'records System with nil actor when no current user exists' do
    Current.user = nil
    described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    expect(JrcHumanAssignmentPolicyEvent.find_by!(account_id: account.id, inbox_id: inbox.id).user_id).to be_nil
    expect(JrcHumanAssignmentPolicyEvent.find_by!(account_id: account.id, inbox_id: nil).user_id).to be_nil
  end

  it 'does not audit a foreign inbox from historical corrupted configuration' do
    foreign_inbox = create(:inbox)
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'enabled' => true, 'max_open' => 2, 'inbox_ids' => [foreign_inbox.id] } })
    described_class.update!(account, enabled: true, max_open: 3, inbox_ids: [inbox.id])
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id).where.not(inbox_id: nil).pluck(:inbox_id)).to eq([inbox.id])
  end

  it 'audits an unscoped disabled configuration change without inventing an impacted inbox' do
    expect(described_class.update!(account, enabled: false, max_open: 3, inbox_ids: []))
      .to eq(enabled: false, max_open: 3, inbox_ids: [])
    events = JrcHumanAssignmentPolicyEvent.where(account_id: account.id)
    expect(events.count).to eq(1)
    expect(events.first.inbox_id).to be_nil
    expect(events.first.user_id).to eq(admin.id)
    expect(events.first.previous_policy).to eq('scope' => 'GLOBAL_ACCOUNT', 'enabled' => false, 'max_open' => 10, 'inbox_ids' => [])
    expect(events.first.next_policy).to eq('scope' => 'GLOBAL_ACCOUNT', 'enabled' => false, 'max_open' => 3, 'inbox_ids' => [])
  end

  it 'audits global configuration changes even when every selected inbox has an override' do
    team = create(:team, account: account, allow_auto_assign: true)
    described_class.update_connection!(account, inbox: inbox, actor: admin, enabled: true, mode: 'direct', team_ids: [team.id], max_open: 5)
    override = described_class.connection_for(account, inbox.id).deep_dup
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    end.to change(JrcHumanAssignmentPolicyEvent, :count).by(1)
    expect(described_class.connection_for(account.reload, inbox.id)).to eq(override)
    global_event = JrcHumanAssignmentPolicyEvent.where(account_id: account.id, inbox_id: nil).sole
    expect(global_event.next_policy).to eq('scope' => 'GLOBAL_ACCOUNT', 'enabled' => true, 'max_open' => 2, 'inbox_ids' => [inbox.id])
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id, inbox_id: inbox.id).count).to eq(1)
  end

  it 'does not audit an unscoped true no-op or treat operational cursor state as configuration' do
    account.update!(custom_attributes: {
                      'jrc_human_assignment' => { 'enabled' => false, 'max_open' => 3, 'inbox_ids' => [], 'last_agent_id' => 42 }
                    })
    expect do
      described_class.update!(account, enabled: false, max_open: 3, inbox_ids: [])
    end.not_to change(JrcHumanAssignmentPolicyEvent, :count)
    expect(account.reload.custom_attributes.dig('jrc_human_assignment', 'last_agent_id')).to eq(42)
  end

  it 'rolls back policy and per-inbox events when the account-global audit insert fails' do
    before = account.reload.custom_attributes.deep_dup
    allow(JrcHumanAssignmentPolicyEvent).to receive(:create!).and_wrap_original do |original, attributes|
      raise ActiveRecord::RecordInvalid if attributes[:inbox_id].nil?

      original.call(attributes)
    end
    expect do
      described_class.update!(account, enabled: true, max_open: 2, inbox_ids: [inbox.id])
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.reload.custom_attributes).to eq(before)
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id)).to be_empty
  end
end
