module JrcProjects
  class Project < ApplicationRecord
    STATUSES = %w[planned active on_hold completed canceled].freeze
    VISIBILITIES = %w[members account private].freeze
    PRIORITIES = %w[low medium high urgent].freeze
    store_accessor :settings, :priority

    def priority
      super.presence || 'medium'
    end

    def contact_locked?
      linked_contact_ids.any?
    end

    belongs_to :account
    belongs_to :owner, class_name: 'User'
    belongs_to :contact, optional: true
    belongs_to :accepted_by, class_name: 'User', optional: true
    alias_attribute :created_by_id, :owner_id
    has_many :operation_links, class_name: 'JrcOperations::Link', dependent: :destroy
    has_many_attached :attachments
    validates :name, length: { maximum: 240 }
    validate :valid_dates
    def valid_dates
      errors.add(:due_on, 'anterior ao inicio') if starts_on && due_on && due_on < starts_on
    end
    has_many :project_members, dependent: :destroy
    has_many :members, through: :project_members, source: :user
    has_many :boards, dependent: :destroy
    has_many :board_columns, through: :boards
    has_many :tasks, dependent: :destroy
    has_many :phases, dependent: :destroy
    has_many :milestones, dependent: :destroy
    has_many :time_entries, dependent: :destroy
    has_one :budget, dependent: :destroy
    validates :key, :name, :status, :visibility, presence: true
    validates :key, uniqueness: { scope: :account_id }, format: { with: /\A[A-Z][A-Z0-9_-]{1,15}\z/ }
    validates :status, inclusion: { in: STATUSES }
    validates :visibility, inclusion: { in: VISIBILITIES }
    validates :priority, inclusion: { in: PRIORITIES }
    validate :preserve_linked_contact, if: :will_save_change_to_contact_id?

    private

    def linked_contact_ids
      return [] unless persisted?

      operation_links.where(account_id: account_id, project_id: id).includes(:ticket, :conversation, :crm_deal).flat_map do |link|
        [link.ticket&.requester_id, link.conversation&.contact_id, link.crm_deal&.contact_id]
      end.compact.uniq
    end

    def preserve_linked_contact
      source_ids = linked_contact_ids
      return if source_ids.empty? || source_ids == [contact_id]

      errors.add(:contact, 'deve preservar o cliente dos registros de origem vinculados')
    end
  end
end
