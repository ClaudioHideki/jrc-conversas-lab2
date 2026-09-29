module JrcProjects
  class Task < ApplicationRecord
    STATUSES = %w[backlog in_progress review completed blocked canceled].freeze
    store_accessor :custom_fields, :labels
    def labels
      super || []
    end
    before_validation :normalize_labels
    validate :valid_labels
    belongs_to :account
    belongs_to :project
    belongs_to :board_column, optional: true
    belongs_to :parent, class_name: 'JrcProjects::Task', optional: true
    belongs_to :assignee, class_name: 'User', optional: true
    belongs_to :created_by, class_name: 'User'
    has_many :subtasks, class_name: 'JrcProjects::Task', foreign_key: :parent_id, dependent: :destroy
    has_many :checklist_items, dependent: :destroy
    has_many :task_comments, dependent: :destroy
    has_many :time_entries, dependent: :restrict_with_error
    has_many_attached :attachments
    validates :title, :status, :priority, presence: true
    validates :title, length: { maximum: 240 }
    validates :status, inclusion: { in: STATUSES }
    validates :priority, inclusion: { in: %w[low medium high urgent] }
    validates :estimated_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    # Unlink explicitly so deletion never changes a task link into a project link.
    has_many :operation_links, class_name: 'JrcOperations::Link', dependent: :restrict_with_error
    has_many :outgoing_dependencies, class_name: 'JrcProjects::TaskDependency', foreign_key: :predecessor_id, dependent: :destroy
    has_many :incoming_dependencies, class_name: 'JrcProjects::TaskDependency', foreign_key: :successor_id, dependent: :destroy
    validate :valid_task_dates
    def valid_task_dates
      errors.add(:due_on, 'anterior ao inicio') if starts_on && due_on && due_on < starts_on
      errors.add(:status, 'divergente da coluna') if board_column && status != board_column.status_key
      if assignee && project && !project.project_members.where(account_id: account_id, project_id: project_id).exists?(user_id: assignee.id)
        errors.add(:assignee, 'adicione este usuario a equipe do projeto')
      end
    end
    validate :parent_belongs_to_project
    validate :parent_is_acyclic, if: :will_save_change_to_parent_id?
    validate :board_and_assignee_belong_to_context

    private

    def normalize_labels
      self.labels = labels.map(&:strip).reject(&:empty?).uniq if labels.is_a?(Array) && labels.all? { |label| label.is_a?(String) }
    end

    def valid_labels
      errors.add(:labels, 'devem ser uma lista de textos') unless labels.is_a?(Array) && labels.all? { |label| label.is_a?(String) }
    end

    def parent_is_acyclic
      ancestor = parent
      visited = [id].compact
      while ancestor
        if visited.include?(ancestor.id)
          errors.add(:parent, 'nao pode formar um ciclo de subtarefas')
          break
        end
        visited << ancestor.id
        ancestor = ancestor.parent
      end
    end

    def parent_belongs_to_project
      errors.add(:parent, 'must belong to project') if parent && parent.project_id != project_id
    end

    def board_and_assignee_belong_to_context
      errors.add(:board_column, 'must belong to project') if board_column && board_column.board.project_id != project_id
      errors.add(:assignee, 'must belong to account') if assignee && !account.users.exists?(assignee.id)
    end
  end
end
