require 'rails_helper'

# Prepared, not executed. Configuration never creates a task or grants the eventual completing agent access.
RSpec.describe JrcContactCenter::EndingActions::ConfigureRule do
  include_context 'with native ending rule configuration'

  it 'persists an explicitly authorized private rule and native audit without exposing its template through account settings' do
    context = JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }
    result = configure_native_ending_rule
    catalogue = JrcContactCenter::EndingActions::Catalogue.new(account: account)
    row = JrcContactCenter::EndingActionVersion.where(account: account).sole
    audit = Audited.audit_class.find(row.source_audit_id)
    expect(catalogue.call.fetch('entries')).to eq([result.fetch(:rule)])
    expect(result.fetch(:revision)).to eq(policy.revision)
    expect([row.actor_user_id, context.keys.index_with { |field| Current.public_send(field) }]).to eq([actor.id, context])
    expect(account.reload.settings.to_json).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'project_id', 'definition_sha256')
    expect(audit.audited_changes.to_json).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'project_id', 'definition_sha256')
    expect(row.inspect).not_to include('SYNTHETIC_PRIVATE_TEMPLATE_7f19')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'keeps the same exact rule retry as a no-op without a second version or audit' do
    first = configure_native_ending_rule
    previous = ending_rule_write_counts
    second = configure_native_ending_rule
    expect(second).to eq(first)
    expect(ending_rule_write_counts).to eq(previous)
  end

  it 'audits an authorized deactivation while keeping prior definitions and an identical inactive retry unchanged' do
    configure_native_ending_rule
    first = JrcContactCenter::EndingActionVersion.where(account: account).sole.attributes.deep_dup
    result = configure_native_ending_rule(rule_input.merge('active' => false))
    before = ending_rule_write_counts
    expect(result.fetch(:rule).fetch('active')).to be(false)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).first.attributes).to eq(first)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).pluck(:revision)).to eq([1, 2])
    expect(configure_native_ending_rule(rule_input.merge('active' => false))).to eq(result)
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'rejects deactivation after a native permission revocation without changing the active rule or its history' do
    configure_native_ending_rule
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    member.update!(custom_role: role)
    before = ending_rule_write_counts
    expect { configure_native_ending_rule(rule_input.merge('active' => false)) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ending_rule_write_counts).to eq(before)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).sole.definition.fetch('entries').first.fetch('active')).to be(true)
  end

  it 'rejects a stale native revision instead of losing another clients changes' do
    revision = policy.revision
    configure_native_ending_rule
    before = ending_rule_write_counts
    changed = rule_input.merge('name' => 'SYNTHETIC stale change')
    expect { configure_native_ending_rule(changed, expected_revision: revision) }
      .to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'revalidates the current native profile even if the command was created before revocation' do
    command = described_class.new(account: account, member: member, input: rule_input, expected_revision: policy.revision)
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    member.update!(custom_role: role)
    before = ending_rule_write_counts
    expect { command.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'does not use a foreign membership as configuration authority for this account' do
    other = create(:account)
    person = create(:user, :contact_center_eligible, account: other, role: :administrator)
    foreign = other.account_users.find_by!(user: person)
    input = rule_input
    before = ending_rule_write_counts
    expect { configure_native_ending_rule(input, acting_member: foreign) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'rejects a corporate coverage revocation without changing the saved history or granting global scope' do
    input = rule_input
    JrcCrm::UserBusinessUnit.where(account: account, user: actor, scope: 'GROUP').find_each { |coverage| coverage.update!(active: false) }
    before = ending_rule_write_counts
    expect { configure_native_ending_rule(input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'rejects a queue mapping changed after the form was loaded instead of accepting the old scope hash' do
    input = rule_input
    unit.update!(settings: { 'issuer_company_id' => issuer.id })
    before = ending_rule_write_counts
    expect { configure_native_ending_rule(input) }.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(ending_rule_write_counts).to eq(before)
  end

  it 'revalidates the actual native project feature without enabling it on behalf of the caller' do
    input = rule_input
    account.disable_features!('jrc_projects')
    before = ending_rule_write_counts
    expect { configure_native_ending_rule(input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ending_rule_write_counts).to eq(before)
    expect(account.reload.feature_enabled?('jrc_projects')).to be(false)
  end

  it 'preserves unrelated rules and old immutable versions when editing one explicitly authorized rule' do
    configure_native_ending_rule
    first = JrcContactCenter::EndingActionVersion.where(account: account).sole.attributes.deep_dup
    configure_native_ending_rule(rule_input.merge('code' => 'SYNTHETIC_SECOND'))
    configure_native_ending_rule(rule_input.merge('name' => 'SYNTHETIC revised'))
    versions = JrcContactCenter::EndingActionVersion.where(account: account).order(:revision)
    expect(versions.pluck(:revision)).to eq([1, 2, 3])
    expect(versions.first.attributes).to eq(first)
    expect(versions.last.definition.fetch('entries').pluck('code')).to eq(%w[SYNTHETIC_RULE SYNTHETIC_SECOND])
    expect(versions.last.definition.fetch('entries').last.fetch('name')).to eq('SYNTHETIC rule')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rolls back the head and native audit if private version persistence fails' do
    input = rule_input
    before = ending_rule_write_counts
    original = account.reload.settings.deep_dup
    context = JrcServiceDesk::NativeExecutionContext::FIELDS.index_with { |field| Current.public_send(field) }
    allow(JrcContactCenter::EndingActionVersion).to receive(:record_change!).and_raise(ActiveRecord::RecordInvalid)
    expect { configure_native_ending_rule(input) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.reload.settings).to eq(original)
    expect(ending_rule_write_counts).to eq(before)
    expect(context.keys.index_with { |field| Current.public_send(field) }).to eq(context)
  end

  it 'lets the currently authorized owner replace an old closed destination without bypassing checks on the new one' do
    configure_native_ending_rule
    project.update!(status: 'completed')
    other = JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'SYNTHETIC replacement destination' },
                                               idempotency_key: SecureRandom.uuid)
    input = rule_input.deep_dup
    values = input.fetch('actions').first.fetch('parameters')
    values['project_id'] = other.id.to_s
    values['attributes']['board_column_id'] = other.board_columns.find_by!(status_key: 'backlog').id.to_s
    result = configure_native_ending_rule(input)
    expect(result.fetch(:rule).fetch('actions').first.fetch('parameters').fetch('project_id')).to eq(other.id.to_s)
    expect(JrcContactCenter::EndingActionVersion.where(account: account).order(:revision).pluck(:revision)).to eq([1, 2])
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end
end
