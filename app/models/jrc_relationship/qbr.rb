class JrcRelationship::Qbr < JrcRelationship::Record
  self.table_name = 'jrc_relationship_qbrs'
  belongs_to :activity, class_name: 'JrcCrm::Activity', optional: true
  validates :title, :scheduled_at, presence: true
  validates :status, inclusion: { in: %w[scheduled completed canceled] }
  validates :summary, presence: true, if: -> { status == 'completed' }
end
