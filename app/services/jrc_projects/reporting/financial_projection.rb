module JrcProjects
  module Reporting
    class FinancialProjection
      def self.call(project:)
        budget = project.budget
        actual = project.time_entries.where(account_id: project.account_id, project_id: project.id, status: 'approved').sum('minutes * COALESCE(hourly_cost_cents, 0) / 60.0').round
        { currency: budget&.currency || 'BRL', planned_cents: budget&.planned_cents || 0, committed_cents: budget&.committed_cents || 0,
          actual_cents: actual, remaining_cents: (budget&.planned_cents || 0) - actual, basis: 'approved_time_entries' }
      end
    end
  end
end
