module JrcOperations
  class OverviewController < BaseController
    def show
      data = { service_desk: nil, projects: nil }
      if JrcServiceDesk::ModulePolicy.new(Access.r2_context(Current.account_user), Current.account).show?
        tickets = Access.tickets(Current.account_user)
        data[:service_desk] = { open: tickets.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: %w[open waiting] }).count }
      end
      if Access.project_access?(Current.account_user)
        projects = Access.projects(Current.account_user)
        tasks = JrcProjects::Task.where(account_id: Current.account.id, project_id: projects.select(:id), assignee_id: Current.user.id).where.not(status: %w[completed canceled])
        data[:projects] = { active: projects.where(status: 'active').count, my_tasks: tasks.count, overdue: tasks.where('due_on < ?', Date.current).count,
          tasks: tasks.order(:due_on).limit(5).as_json(only: %i[id project_id title due_on status]) }
      end
      render json: { data: data }
    end
    def agenda
      render json: Agenda.new(account_user: Current.account_user,
                             filters: params.permit(:from, :to, :source, :view, :user_id).to_h).call
    end
  end
end
