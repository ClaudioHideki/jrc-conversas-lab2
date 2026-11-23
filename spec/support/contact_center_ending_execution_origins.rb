# Synthetic native fixtures only. Evidence is deliberately unarmed; it never enables an executor.
RSpec.shared_context 'with native ending execution original evidence' do
  include_context 'with a native ending action queue scope'

  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:source_call) { new_origin_source_call }
  let(:source_leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: source_call, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: source_call.started_at,
                                      answered_at: source_call.answered_at)
  end
  let(:qualification) do
    source_leg
    source_call.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: source_call)
  end
  let(:origin) do
    qualification
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: qualification.id)
  end

  def new_origin_source_call(started_at: Time.current)
    JrcContactCenter::CallSession.create!(account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: started_at, answered_at: started_at,
                                          current_unit: unit, current_queue: queue)
  end

  def prepare_origin_configuration
    policy = JrcContactCenter::AcwPolicy.new(account: account)
    entry = { 'code' => 'SYNTHETIC_ORIGIN_REASON', 'name' => 'SYNTHETIC origin reason', 'category' => 'SYNTHETIC',
              'description' => '', 'order' => 0, 'active' => true }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_reason_catalog: [entry], voice_reason_required_queue_ids: [queue.id.to_s],
                                                  voice_reason_confirmation: true, expected_revision: policy.revision)
    project = JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'SYNTHETIC origin destination' },
                                                 idempotency_key: SecureRandom.uuid)
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member, input: origin_rule_document(project),
                                                       expected_revision: policy.revision).call
  end

  def origin_rule_document(project)
    attributes = { 'title' => 'SYNTHETIC unarmed original evidence', 'priority' => 'medium', 'estimated_minutes' => 0,
                   'board_column_id' => project.board_columns.find_by!(status_key: 'backlog').id.to_s }
    parameters = { 'project_id' => project.id.to_s, 'due_after_days' => nil, 'attributes' => attributes }
    { 'code' => 'SYNTHETIC_ORIGIN_RULE', 'name' => 'SYNTHETIC origin rule', 'reason_code' => 'SYNTHETIC_ORIGIN_REASON',
      'queue_id' => queue.id.to_s, 'scope_revision' => scope.integrity_sha256, 'timing' => 'acw_completed', 'active' => true,
      'execution_mode' => 'automatic', 'conditions' => { 'outcome_codes' => [] },
      'actions' => [{ 'kind' => 'project_task', 'parameters' => parameters }] }
  end

  def complete_origin_qualification
    JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(
      qualification, { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' }
    )
  end

  def guarded_origin_sql(statement)
    ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(statement) }
  end

  before do
    account.enable_features!('jrc_contact_center', 'jrc_projects')
    member.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.project.create' => true })
    business
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) { prepare_origin_configuration }
  end
end
