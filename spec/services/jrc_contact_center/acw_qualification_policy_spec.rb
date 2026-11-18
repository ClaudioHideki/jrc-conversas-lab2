require 'rails_helper'

RSpec.describe JrcContactCenter::AcwQualificationPolicy do
  let(:account) { create(:account) }
  let(:agent) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, name: 'SYNTHETIC ACW snapshot', code: 'ACW', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, name: 'SYNTHETIC ACW snapshot', code: 'ACW') }
  let(:team) { create(:team, account: account) }
  let(:general) { { id: 'general', reason_code: 'order', scope: 'general', scope_id: nil, active: true, limit_seconds: 180 } }
  let(:rules) { [general, general.merge(id: 'team', scope: 'team', scope_id: team.id, limit_seconds: 120),
                         general.merge(id: 'queue', scope: 'queue', scope_id: queue.id, limit_seconds: 60)] }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account.reload) }
  let(:manager) { JrcContactCenter::QualificationManager.new(account: account, member: member) }
  let(:session) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                         direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago)
  end
  let!(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: session, account_user: member, queue: queue,
                                     direction: 'inbound', status: 'connected', started_at: session.started_at, answered_at: session.answered_at)
  end
  let(:record) do
    session.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.find_by!(account: account, call_session: session, account_user: member)
  end
  let(:event) { JrcContactCenter::AgentStateEvent.find_by!(account: account, external_event_id: "qualification:#{record.id}:pending") }

  before do
    account.enable_features!('jrc_contact_center')
    team.add_members([agent.id])
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: rules, expected_revision: policy.revision)
  end

  it 'uses the answered leg origin and persists the queue rule in native completion' do
    expect(record.acw_limit_seconds).to eq(180)
    manager.complete!(record, reason_code: 'order', outcome_code: 'completed')
    expect(record.reload).to have_attributes(acw_limit_seconds: 60, reason_code: 'order')
    expect(event.metadata.fetch(described_class::KEY)).to include('queue_id' => queue.id, 'team_ids' => [team.id.to_s])
  end

  it 'uses team precedence when the answered leg has no queue and does not infer a transferred current queue' do
    leg.update!(queue: nil)
    session.update!(current_queue_id: queue.id)
    manager.complete!(record, reason_code: 'order', outcome_code: 'completed')
    expect(record.reload.acw_limit_seconds).to eq(120)
    expect(event.metadata.fetch(described_class::KEY).fetch('queue_id')).to be_nil
  end

  it 'uses the general reason rule when no queue or team rule matches the native snapshot' do
    leg.update!(queue: nil)
    team.remove_members([agent.id])
    manager.complete!(record, reason_code: 'order', outcome_code: 'completed')
    expect(record.reload.acw_limit_seconds).to eq(180)
  end

  it 'keeps the original snapshot and selected limit after later configuration and membership changes' do
    before = event.metadata.deep_dup
    policy.update!({ voice: 300, whatsapp: 240 }, voice_rules: [], expected_revision: policy.revision)
    team.remove_members([agent.id])
    manager.complete!(record, reason_code: 'order', outcome_code: 'completed')
    expect(record.reload.acw_limit_seconds).to eq(60)
    expect(event.reload.metadata).to eq(before)
    expect(manager.complete!(record, reason_code: 'other', outcome_code: 'pending').reload.acw_limit_seconds).to eq(60)
  end

  it 'keeps legacy pending qualifications on their captured global limit when new rules are added later' do
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: [], expected_revision: policy.revision)
    record
    before = event.metadata.deep_dup
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: rules, expected_revision: policy.revision)
    manager.complete!(record, reason_code: 'order', outcome_code: 'completed')
    expect(record.reload.acw_limit_seconds).to eq(180)
    expect(event.reload.metadata).to eq(before)
    expect(before).not_to have_key(described_class::KEY)
  end

  it 'blocks overlapping native teams at the same level without completing or resolving the attendance' do
    leg.update!(queue: nil)
    other = create(:team, account: account)
    other.add_members([agent.id])
    values = rules + [general.merge(id: 'other_team', scope: 'team', scope_id: other.id, limit_seconds: 30)]
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: values, expected_revision: policy.revision)
    expect { manager.complete!(record, reason_code: 'order', outcome_code: 'completed') }
      .to raise_error(JrcContactCenter::AcwRulePrecedence::Conflict)
    expect(record.reload.completed_at).to be_nil
    expect(event.reload.ended_at).to be_nil
    expect(record.acw_limit_seconds).to eq(180)
  end

  it 'uses the captured default for an unrelated reason without applying another reason rule' do
    manager.complete!(record, reason_code: 'information', outcome_code: 'completed')
    expect(record.reload.acw_limit_seconds).to eq(180)
  end

  it 'rejects a tampered snapshot from another account rather than silently falling back' do
    data = event.metadata.deep_dup
    data.fetch(described_class::KEY)['account_id'] = create(:account).id
    event.update!(metadata: data)
    expect { manager.complete!(record, reason_code: 'order', outcome_code: 'completed') }
      .to raise_error(JrcContactCenter::OperationError, 'invalid_acw_rule_snapshot')
    expect(record.reload.completed_at).to be_nil
  end
end
