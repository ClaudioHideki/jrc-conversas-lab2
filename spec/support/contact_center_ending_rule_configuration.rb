# Every grant below belongs only to its explicitly synthetic native test account.
RSpec.shared_context 'with native ending rule configuration' do
  include_context 'with a native ending action queue scope'

  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account) }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'SYNTHETIC automation destination' },
                                       idempotency_key: SecureRandom.uuid)
  end
  let(:column) { project.board_columns.find_by!(status_key: 'backlog') }
  let(:rule_input) do
    { 'code' => 'SYNTHETIC_RULE', 'name' => 'SYNTHETIC rule', 'reason_code' => 'SYNTHETIC_REASON', 'queue_id' => queue.id.to_s,
      'scope_revision' => scope.integrity_sha256, 'timing' => 'call_end', 'active' => true,
      'conditions' => { 'outcome_codes' => [] }, 'actions' => [{ 'kind' => 'project_task', 'parameters' => {
        'project_id' => project.id.to_s, 'due_after_days' => nil, 'attributes' => {
          'title' => 'SYNTHETIC_PRIVATE_TEMPLATE_7f19', 'priority' => 'medium', 'estimated_minutes' => 0,
          'board_column_id' => column.id.to_s
        }
      } }] }
  end

  def configure_native_ending_rule(input = rule_input, expected_revision: policy.revision, acting_member: member)
    # Preserve an actual application rollback boundary inside RSpec's fixture transaction.
    Account.transaction(requires_new: true) do
      JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: acting_member, input: input,
                                                         expected_revision: expected_revision).call
    end
  end

  def ending_rule_write_counts
    [JrcContactCenter::EndingActionVersion.where(account: account).count, Audited.audit_class.where(associated: account).count,
     JrcProjects::Task.where(account: account).count]
  end

  before do
    account.enable_features!('jrc_contact_center', 'jrc_projects')
    member.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.project.create' => true })
    business
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    entry = { 'code' => 'SYNTHETIC_REASON', 'name' => 'SYNTHETIC reason', 'category' => 'SYNTHETIC',
              'description' => '', 'order' => 0, 'active' => true }
    Current.set(user: actor, account: account, account_user: member) do
      policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], voice_reason_required_queue_ids: [queue.id.to_s],
                                                    voice_reason_confirmation: true, expected_revision: policy.revision)
    end
  end
end
