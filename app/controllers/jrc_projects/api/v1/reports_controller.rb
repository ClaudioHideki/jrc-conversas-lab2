require 'csv'
module JrcProjects
  module Api
    module V1
      class ReportsController < BaseController
        STATUS_LABELS = { 'backlog' => 'A fazer', 'in_progress' => 'Em andamento', 'review' => 'Em validação',
                          'completed' => 'Concluído', 'blocked' => 'Bloqueado', 'canceled' => 'Cancelado' }.freeze
        PRIORITY_LABELS = { 'low' => 'Baixa', 'medium' => 'Média', 'high' => 'Alta', 'urgent' => 'Urgente' }.freeze
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
            csv << ['Tarefa', 'Situação', 'Prioridade', 'Início', 'Prazo', 'Estimativa (minutos)']
            project.tasks.order(:id).limit(10000).each do |task|
              csv << [JrcOperations::Csv.safe(task.title), STATUS_LABELS.fetch(task.status), PRIORITY_LABELS.fetch(task.priority),
                      task.starts_on, task.due_on, task.estimated_minutes]
            end
          end
          send_data "\uFEFF" + content, filename: "#{project.key}-tarefas.csv", type: 'text/csv; charset=utf-8'
        end
      end
    end
  end
end
