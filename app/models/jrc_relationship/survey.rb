class JrcRelationship::Survey < JrcRelationship::Record
  include JrcRelationship::SignalDispatch
  self.table_name = 'jrc_relationship_surveys'
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment', optional: true
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  belongs_to :contact, optional: true
  belongs_to :contract, class_name: 'JrcCrm::Contract', optional: true
  belongs_to :product, class_name: 'JrcCrm::Product', optional: true
  belongs_to :definition, class_name: 'JrcRelationship::SurveyDefinition', optional: true
  belongs_to :rule, class_name: 'JrcRelationship::SurveyRule', optional: true
  belongs_to :execution_member, class_name: 'AccountUser', optional: true
  belongs_to :team, optional: true
  belongs_to :agent, class_name: 'User', optional: true
  validates :kind, inclusion: { in: %w[nps csat ces custom] }
  validates :token_digest, :expires_at, presence: true
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }, allow_nil: true
  validates :comment, length: { maximum: 4000 }
  validates :status, inclusion: { in: %w[awaiting scheduled available queued dispatching sent delivered responded expired failed blocked unknown] }
  validates :treatment_status, inclusion: { in: %w[untreated in_progress treated] }
  validates :source_type, inclusion: { in: %w[Conversation JrcServiceDesk::Ticket JrcRelationship::Qbr Call JrcCrm::Activity] }, allow_nil: true
  validates :contact, :definition, :rule, :source_id, :cycle_key, :rule_version, :definition_version,
            presence: true, if: -> { source_type.present? }
  validates :execution_member, presence: true, on: :create, if: -> { source_type.present? }
  validate :preserve_sent_definition
  after_create_commit :enqueue_shared_dispatch

  def questions
    definition_snapshot['questions'].presence || [{ 'key' => 'score', 'text' => metadata['question'], 'type' => 'scale',
                                                    'min' => 0, 'max' => 10, 'required' => true }]
  end

  private

  def enqueue_shared_dispatch
    return unless source_type.present? && status == 'scheduled'

    JrcRelationship::SurveyDispatchJob.set(wait_until: scheduled_at).perform_later(id)
  end

  def preserve_sent_definition
    preserve_definition_fields
    preserve_published_metadata
    return unless responded_at_in_database && changes.keys.intersect?(%w[answers score comment classification responded_at])

    errors.add(:base, 'survey responses are immutable')
  end

  def preserve_definition_fields
    frozen_fields = %w[kind owner_id assignment_id company_id contact_id source_type source_id cycle_key rule_id rule_version
                       definition_id definition_version
                       definition_snapshot rule_snapshot contract_id product_id execution_member_id team_id agent_id]
    errors.add(:base, 'the dispatched survey definition and origin are immutable') if persisted? && changes.keys.intersect?(frozen_fields)
  end

  def preserve_published_metadata
    errors.add(:base, 'the published survey question is immutable') if persisted? && metadata['question'] != metadata_in_database['question']
    if persisted? && metadata['commercial_origin'] != metadata_in_database['commercial_origin']
      errors.add(:base, 'the published commercial origin is immutable')
    end
    return unless persisted? && metadata['attendance_origin'] != metadata_in_database['attendance_origin']

    errors.add(:base, 'the published attendance origin is immutable')
  end
end
