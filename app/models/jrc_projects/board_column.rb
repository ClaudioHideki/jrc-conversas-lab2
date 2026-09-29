module JrcProjects
  class BoardColumn < ApplicationRecord
    belongs_to :account
    belongs_to :board
    has_many :tasks, dependent: :restrict_with_error
    validates :name, :status_key, presence: true
    validates :status_key, inclusion: { in: %w[backlog in_progress review completed blocked canceled] }
    validates :wip_limit, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
    validate :preserve_task_states
    def preserve_task_states
      errors.add(:status_key, 'nao pode mudar enquanto a coluna tiver tarefas') if persisted? && will_save_change_to_status_key? && tasks.exists?
      errors.add(:wip_limit, 'menor que a quantidade de tarefas nesta coluna') if persisted? && wip_limit && tasks.count > wip_limit
    end
  end
end
