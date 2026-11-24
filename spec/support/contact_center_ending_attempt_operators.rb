# Only explicitly synthetic current-account agents; no production grants.
RSpec.shared_context 'with native ending attempt operators' do
  def attempt_operator
    person = create(:user, :contact_center_eligible, account: account, role: :agent)
    operator = account.account_users.find_by!(user: person)
    operator.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.task.create' => true })
    JrcCrm::UserBusinessUnit.create!(account: account, user: person, scope: 'GROUP', active: true, structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: operator, active: true, role: 'agent', priority: 1)
    project = JrcProjects::Project.where(account: account).sole
    JrcProjects::ProjectMember.create!(account: account, project: project, user: person, role: 'member')
    operator
  end

  def completed_attempt_source(operator)
    call = new_origin_source_call
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    row = JrcContactCenter::Qualification.find_by!(account: account, account_user: operator, call_session: call)
    JrcContactCenter::QualificationManager.new(account: account, member: operator).complete!(
      row, { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' }
    )
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: row.id)
  end
end
