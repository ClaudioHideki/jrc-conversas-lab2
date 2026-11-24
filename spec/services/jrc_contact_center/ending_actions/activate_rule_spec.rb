require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ActivateRule do
  include_context 'with native ending execution original evidence'

  let(:request_key) { SecureRandom.uuid }

  def activate_native_ending_rule(code: 'SYNTHETIC_ORIGIN_RULE', revision: JrcContactCenter::AcwPolicy.new(account: account).revision)
    described_class.new(account: account, member: member, rule_code: code, request_key: request_key, expected_revision: revision).call
  end

  it 'records explicit actor, version and source timezone without creating a destination effect' do
    row = activate_native_ending_rule
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    expect(row).to have_attributes(version_id: version.id, actor_account_user_id: member.id, actor_user_id: actor.id,
                                   source_timezone: unit.timezone, request_key: request_key)
    expect(row.rule_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(row.created_at).to be_present
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not activate anything merely because a configuration or call origin exists' do
    origin
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'returns the same reviewed activation for an identical request without rewriting its timestamp or high-water marks' do
    first = activate_native_ending_rule.attributes
    expect { activate_native_ending_rule }.not_to change(JrcContactCenter::EndingActionReadiness, :count)
    expect(activate_native_ending_rule.attributes).to eq(first)
  end

  it 'rechecks current native configuration authority before returning an earlier activation' do
    first = activate_native_ending_rule.attributes
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view]))
    expect { activate_native_ending_rule }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).sole.attributes).to eq(first)
  end

  it 'rejects a stale revision without creating prospective metadata' do
    expect { activate_native_ending_rule(revision: 'SYNTHETIC_STALE') }
      .to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'rejects an unknown rule without choosing another active rule' do
    expect { activate_native_ending_rule(code: 'SYNTHETIC_UNKNOWN') }
      .to raise_error(JrcContactCenter::OperationError, 'ending_action_not_ready')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'does not infer an execution mode for a compatible legacy definition' do
    project = JrcProjects::Project.where(account: account).sole
    input = origin_rule_document(project).except('execution_mode')
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member, input: input,
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
    expect { activate_native_ending_rule }.to raise_error(JrcContactCenter::OperationError, 'ending_action_not_ready')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'requires fresh destination permissions rather than granting access from the saved template' do
    account.disable_features!('jrc_projects')
    expect { activate_native_ending_rule }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'rejects a source mapping changed since the rule was saved' do
    unit.update!(settings: { 'issuer_company_id' => issuer.id })
    expect { activate_native_ending_rule }.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
  end

  it 'rejects reuse of an activation request for a changed rule version' do
    first = activate_native_ending_rule.attributes
    project = JrcProjects::Project.where(account: account).sole
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member,
                                                       input: origin_rule_document(project).merge('name' => 'SYNTHETIC revised'),
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
    expect { activate_native_ending_rule }.to raise_error(JrcContactCenter::OperationError, 'ending_activation_request_conflict')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).sole.attributes).to eq(first)
  end
end
