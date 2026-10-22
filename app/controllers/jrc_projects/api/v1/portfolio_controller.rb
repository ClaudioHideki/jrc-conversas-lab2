class JrcProjects::Api::V1::PortfolioController < JrcProjects::Api::V1::BaseController
  def show
    projects = JrcOperations::Access.projects(Current.account_user)
    tasks = JrcProjects::Task.where(account_id: Current.account.id, project_id: projects.select(:id))
    task_statuses = tasks.group(:status).count
    render json: {
      data: {
        total: projects.count, by_status: projects.group(:status).count,
        overdue: projects.where.not(status: %w[completed canceled]).where('due_on < ?', Date.current).count,
        tasks: task_statuses, tasks_total: task_statuses.values.sum,
        overdue_tasks: tasks.where.not(status: %w[completed canceled]).where('due_on < ?', Date.current).count,
        deliveries: deliveries(projects), filter_options: filter_options(projects),
        scope: JrcOperations::Access.admin?(Current.account_user) ? 'account' : 'visible_projects'
      }
    }
  end

  private

  def deliveries(projects)
    first_month = Date.current.beginning_of_month - 2.months
    next_period = first_month + 6.months
    planned = projects.where.not(status: 'canceled').where(due_on: first_month...next_period)
                      .group(Arel.sql("DATE_TRUNC('month', due_on)")).count
                      .transform_keys { |month| month.strftime('%Y-%m') }
    zone = JrcProjects::Project.connection.quote(Time.zone.tzinfo.name)
    completed_month = "DATE_TRUNC('month', completed_at AT TIME ZONE 'UTC' AT TIME ZONE #{zone})"
    completed = projects.where(status: 'completed', completed_at: first_month.in_time_zone...next_period.in_time_zone)
                        .group(Arel.sql(completed_month)).count.transform_keys { |month| month.strftime('%Y-%m') }
    Array.new(6) do |offset|
      month = (first_month + offset.months).strftime('%Y-%m')
      { month: month, planned: planned.fetch(month, 0), completed: completed.fetch(month, 0) }
    end
  end

  def filter_options(projects)
    owners = User.where(id: projects.select(:owner_id)).order(:name, :id).pluck(:id, :name)
    contacts = Current.account.contacts.where(id: projects.select(:contact_id)).order(:name, :id).pluck(:id, :name)
    {
      owners: owners.map { |id, name| { id: id, name: name } },
      contacts: contacts.map { |id, name| { id: id, name: name } }
    }
  end
end
