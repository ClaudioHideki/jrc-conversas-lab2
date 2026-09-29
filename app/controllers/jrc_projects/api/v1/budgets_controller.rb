module JrcProjects
  module Api
    module V1
      class BudgetsController < BaseController
        def show
          project = scoped_project
          authorize_capability!('projects.budget.view', project:)
          render json: { data: Reporting::FinancialProjection.call(project:) }
        end

        def update
          project = scoped_project
          project.with_lock do
            authorize_capability!('projects.budget.manage', project: project)
            budget = project.budget || project.build_budget(account: Current.account)
            before = budget.attributes
            budget.update!(params.require(:budget).permit(:planned_cents, :committed_cents, :currency))
            if budget.saved_changes.any?
              AuditEvent.record!(account: Current.account, actor: Current.user, action: 'projects.budget.updated', auditable: project,
                                 before_data: before, after_data: budget.attributes, correlation_id: correlation_id)
            end
          end
          render json: { data: Reporting::FinancialProjection.call(project:) }
        end
      end
    end
  end
end
