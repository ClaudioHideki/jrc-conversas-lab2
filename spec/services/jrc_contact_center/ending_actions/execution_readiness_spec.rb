require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ExecutionReadiness do
  include_context 'with native ending execution original evidence'

  def activate_readiness
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                       request_key: SecureRandom.uuid,
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def readiness_for(original = origin, code = 'SYNTHETIC_ORIGIN_RULE')
    described_class.new(account: account, origin: original).call(code)
  end

  def revise_readiness_rule(changes)
    project = JrcProjects::Project.where(account: account).sole
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member,
                                                       input: origin_rule_document(project).merge(changes),
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  it 'leaves every existing attendance ineligible when a rule is explicitly activated later' do
    original = origin
    activation = activate_readiness
    expect(activation.cutoff_call_id).to be >= original.call_session_id
    expect(activation.cutoff_leg_id).to be >= original.call_leg_id
    expect { readiness_for(original) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'admits metadata for a newly observed native attendance without creating a task or granting permissions' do
    activation = activate_readiness
    expect(readiness_for.id).to eq(activation.id)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'retains readiness only for exactly unchanged rules when an unrelated rule is saved' do
    activation = activate_readiness
    revise_readiness_rule('code' => 'SYNTHETIC_UNARMED_RULE', 'name' => 'SYNTHETIC separate rule')
    original = origin
    expect(readiness_for(original).id).to eq(activation.id)
    expect { readiness_for(original, 'SYNTHETIC_UNARMED_RULE') }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not grant the previous readiness to an edited rule' do
    activate_readiness
    revise_readiness_rule('name' => 'SYNTHETIC changed rule')
    expect { readiness_for }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not inherit old readiness through deactivation and reactivation' do
    activate_readiness
    revise_readiness_rule('active' => false)
    revise_readiness_rule('active' => true)
    expect { readiness_for }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'permanently blocks an already pending original action even if its prior readiness still exists after reactivation' do
    activate_readiness
    original = origin
    expect(readiness_for(original)).to be_persisted
    revise_readiness_rule('active' => false)
    revise_readiness_rule('active' => true)
    expect { readiness_for(original) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'requires the current source timezone to match the reviewed timezone instead of retiming a pending deadline' do
    activation = activate_readiness
    original = origin
    unit.update!(timezone: activation.source_timezone == 'UTC' ? 'America/Sao_Paulo' : 'UTC')
    expect { readiness_for(original) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a late historical call even if it receives new IDs after activation' do
    activation = activate_readiness
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    earlier = version.created_at + ((activation.created_at - version.created_at) / 2)
    historical = new_origin_source_call(started_at: earlier)
    leg = JrcContactCenter::CallLeg.create!(account: account, call_session: historical, account_user: member, queue: queue,
                                            direction: 'inbound', status: 'connected', started_at: earlier, answered_at: earlier)
    historical.update!(status: 'ended', ended_at: Time.current)
    original = JrcContactCenter::EndingActionOrigin.find_by!(account: account, call_session_id: historical.id, call_leg_id: leg.id)
    expect(original.call_session_id).to be > activation.cutoff_call_id
    expect { readiness_for(original) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps the original account boundary even when an origin ID is known' do
    activation = activate_readiness
    original = origin
    other = create(:account)
    expect { described_class.new(account: other, origin: original).call(activation.rule_code) }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
