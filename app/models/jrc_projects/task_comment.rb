module JrcProjects
  class TaskComment < ApplicationRecord
    belongs_to :account
    belongs_to :task
    belongs_to :user
    has_many_attached :inline_images
    validates :body, presence: true
    validates :content_format, inclusion: { in: %w[plain_text markdown] }
    validates :body, length: { maximum: 100_000 }, if: -> { content_format == 'markdown' }
    validates :request_key, format: { with: /\A[a-zA-Z0-9-]{16,80}\z/ }, allow_nil: true
  end
end
