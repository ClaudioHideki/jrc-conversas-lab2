module JrcProjects
  module Api
    module V1
      class PortfolioController < BaseController
        def show
          projects = JrcOperations::Access.projects(Current.account_user)
          tasks = Task.where(account_id: Current.account.id, project_id: projects.select(:id))
          render json: { data: { total: projects.count, by_status: projects.group(:status).count,
            overdue: projects.where.not(status: %w[completed canceled]).where('due_on < ?', Date.current).count,
            tasks: tasks.group(:status).count, scope: JrcOperations::Access.admin?(Current.account_user) ? 'account' : 'visible_projects' } }
        end
      end
    end
  end
end
