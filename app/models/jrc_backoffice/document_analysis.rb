class JrcBackoffice::DocumentAnalysis < ApplicationRecord
  self.table_name = 'jrc_backoffice_document_analyses'
  belongs_to :document_version, class_name: 'JrcBackoffice::DocumentVersion'
  validates :analyzer_version, presence: true
  validates :state, inclusion: { in: %w[review_required rejected] }
  validates :document_version_id, uniqueness: true
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Analysis evidence is immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Analysis evidence is immutable' }
end
