module JrcProjects
  module Reporting
    class Dashboard
      def self.call(account:)
        projects = Project.where(account:)
        tasks = Task.where(account:)
        { projects: projects.group(:status).count, tasks: tasks.group(:status).count,
          overdue_tasks: tasks.where('due_on < ?', Date.current).where.not(status: 'completed').count,
          time_minutes: TimeEntry.where(account:).sum(:minutes) }
      end
    end
  end
end
