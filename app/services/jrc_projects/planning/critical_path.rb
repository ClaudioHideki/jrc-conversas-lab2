module JrcProjects
  module Planning
    class CriticalPath
      def self.call(project:)
        tasks = project.tasks.to_a
        ids = tasks.map(&:id)
        edges = TaskDependency.where(account_id: project.account_id, predecessor_id: ids, successor_id: ids).pluck(:predecessor_id, :successor_id)
        calculate(tasks: tasks, edges: edges)
      end
      # Pure graph routine also used by offline regression tests; no recursive stack overflow.
      def self.calculate(tasks:, edges:)
        by_id = tasks.to_h { |task| [task.id, task] }
        incoming = by_id.transform_values { 0 }
        children = Hash.new { |hash, key| hash[key] = [] }
        edges.each { |from, to| incoming[to] += 1; children[from] << to }
        queue = incoming.select { |_id, degree| degree.zero? }.keys.sort
        distance = by_id.transform_values { |task| task.estimated_minutes.to_i }
        parent = {}; seen = 0; cursor = 0
        while cursor < queue.length
          id = queue[cursor]; cursor += 1; seen += 1
          children[id].each do |child|
            candidate = distance[id] + by_id[child].estimated_minutes.to_i
            if candidate >= distance[child]
              distance[child] = candidate; parent[child] = id
            end
            incoming[child] -= 1; queue << child if incoming[child].zero?
          end
        end
        raise Errors::DependencyCycle, 'O projeto contem dependencias circulares.' unless seen == tasks.length
        last = distance.max_by { |id, value| [value, id] }&.first
        duration = last ? distance[last] : 0; path = []
        while last
          path.unshift(last); last = parent[last]
        end
        { task_ids: path, duration_minutes: duration, warnings: [] }
      end
    end
  end
end
