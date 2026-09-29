require 'csv'
module JrcProjects
  module Api
    module V1
      class ReportsController < BaseController
        def index
          project = scoped_project
          authorize_capability!('projects.report.view', project: project)
          render json: { data: { tasks: project.tasks.group(:status).count, time_minutes: project.time_entries.sum(:minutes) } }
        end
        def export
          project = scoped_project
          authorize_capability!('projects.report.export', project: project)
          raise ArgumentError, 'Exportacao limitada a 10000 tarefas.' if project.tasks.count > 10000
          content = CSV.generate(col_sep: ';') do |csv|
            csv << %w[Tarefa Status Prioridade Inicio Prazo Estimativa_minutos]
            project.tasks.order(:id).limit(10000).each { |task| csv << [JrcOperations::Csv.safe(task.title), task.status, task.priority, task.starts_on, task.due_on, task.estimated_minutes] }
          end
          send_data "\uFEFF" + content, filename: "#{project.key}-tarefas.csv", type: 'text/csv; charset=utf-8'
        end
      end
    end
  end
end
