require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ReadinessStatus do
  include_context 'with native ending rule configuration'

  before { configure_native_ending_rule(rule_input.merge('execution_mode' => 'automatic')) }

  def read_native_readiness(code: 'SYNTHETIC_RULE', revision: policy.revision)
    described_class.new(account: account, member: member, rule_code: code, expected_revision: revision).call
  end

  def explicitly_activate_current_rule
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_RULE',
                                                      request_key: SecureRandom.uuid, expected_revision: policy.revision).call
  end

  it 'keeps an unreviewed rule empty without implicitly creating readiness or tasks on read' do
    expect(read_native_readiness).to eq(last_review: nil, applicable_review: nil, reviewed_revision: policy.revision)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'reloads the actual persisted receipt without returning private templates or actor identities' do
    receipt = explicitly_activate_current_rule
    first = read_native_readiness
    expect(first.fetch(:last_review)).to include(id: receipt.id.to_s, version_id: receipt.version_id.to_s, prospective_only: true)
    expect(first.fetch(:applicable_review)).to eq(first.fetch(:last_review))
    expect(read_native_readiness).to eq(first)
    expect(first.to_json).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'actor_user_id', 'actor_account_user_id', 'request_key')
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
  end

  it 'retains the exact unchanged review after an unrelated rule produces a new catalogue version' do
    receipt = explicitly_activate_current_rule
    configure_native_ending_rule(rule_input.merge('code' => 'SYNTHETIC_OTHER', 'name' => 'SYNTHETIC unrelated', 'execution_mode' => 'automatic'))
    expect(read_native_readiness.fetch(:applicable_review).fetch(:id)).to eq(receipt.id.to_s)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'preserves historical metadata but does not revive its applicability after deactivation and reactivation' do
    receipt = explicitly_activate_current_rule
    configure_native_ending_rule(rule_input.merge('active' => false, 'execution_mode' => 'automatic'))
    configure_native_ending_rule(rule_input.merge('active' => true, 'execution_mode' => 'automatic'))
    result = read_native_readiness
    expect(result.fetch(:last_review).fetch(:id)).to eq(receipt.id.to_s)
    expect(result.fetch(:applicable_review)).to be_nil
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'does not expose a preceding private definition after its current parameters have changed' do
    explicitly_activate_current_rule
    changed = rule_input.deep_dup.merge('execution_mode' => 'automatic')
    changed.fetch('actions').first.fetch('parameters').fetch('attributes')['title'] = 'SYNTHETIC changed private task'
    configure_native_ending_rule(changed)
    expect(read_native_readiness.values_at(:last_review, :applicable_review)).to eq([nil, nil])
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'revalidates the current configuration role before showing any review metadata' do
    explicitly_activate_current_rule
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view]))
    expect { read_native_readiness }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects current destination authority that was removed after the review' do
    explicitly_activate_current_rule
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_projects_project_view])
    member.update!(custom_role: role)
    expect { read_native_readiness }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects a stale loaded revision instead of labelling a different current rule as reviewed' do
    revision = policy.revision
    explicitly_activate_current_rule
    configure_native_ending_rule(rule_input.merge('name' => 'SYNTHETIC revised', 'execution_mode' => 'automatic'))
    expect { read_native_readiness(revision: revision) }.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
  end

  it 'does not borrow a member from another account to obtain its activation history' do
    explicitly_activate_current_rule
    other = create(:account)
    other.enable_features!('jrc_contact_center')
    expect do
      described_class.new(account: other, member: member, rule_code: 'SYNTHETIC_RULE', expected_revision: policy.revision).call
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingActionReadiness.where(account: other)).to be_empty
  end

  it 'does not use the existence of a rule code as authority to read an unknown private rule' do
    expect { read_native_readiness(code: 'SYNTHETIC_UNKNOWN') }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not embed the private rule template in actual SQL query text while matching its native digest' do
    explicitly_activate_current_rule
    queries = []
    subscriber = ->(*, payload) { queries << payload.fetch(:sql) }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { read_native_readiness }
    expect(queries).not_to be_empty
    expect(queries.join).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
