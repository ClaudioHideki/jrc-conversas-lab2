require 'set'
module JrcProjects
  module Planning
    class DependencyGraph
      def self.add!(predecessor:, successor:, kind: 'finish_to_start')
        raise ArgumentError, 'Tipo de dependencia nao suportado.' unless kind == 'finish_to_start'
        raise ActiveRecord::RecordNotFound unless predecessor.account_id == successor.account_id
        predecessor.project.with_lock do
          predecessor.reload
          successor.reload
          raise Errors::DependencyCycle, 'Dependencia circular ou entre projetos diferentes.' if predecessor.id == successor.id || predecessor.project_id != successor.project_id
          existing = TaskDependency.find_by(account: predecessor.account, predecessor: predecessor, successor: successor)
          next existing if existing

          raise ArgumentError, 'A tarefa sucessora ja esta concluida.' if successor.status == 'completed' && !%w[completed canceled].include?(predecessor.status)
          raise Errors::DependencyCycle, 'Esta dependencia formaria um ciclo.' if reachable?(successor, predecessor)
          TaskDependency.create!(account: predecessor.account, predecessor: predecessor, successor: successor, kind: kind)
        end
      end
      def self.reachable?(from, target)
        edges = TaskDependency.where(account_id: from.account_id, predecessor_id: from.project.tasks.where(account_id: from.account_id).select(:id), successor_id: from.project.tasks.where(account_id: from.account_id).select(:id)).pluck(:predecessor_id, :successor_id).group_by(&:first)
        pending = [from.id]; visited = Set.new
        until pending.empty?
          id = pending.pop
          return true if id == target.id
          next unless visited.add?(id)
          pending.concat(Array(edges[id]).map(&:last))
        end
        false
      end
    end
  end
end
