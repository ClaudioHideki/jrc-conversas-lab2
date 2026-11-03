class JrcCustomers::Taxonomy < ApplicationRecord
  self.table_name = 'jrc_customer_taxonomies'

  KINDS = %w[segment].freeze
  MODULES = %w[crm backoffice service_desk projects relationship campaigns].freeze

  belongs_to :account
  has_many :overrides, class_name: 'JrcCustomers::SegmentOverride', dependent: :restrict_with_error

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id kind], case_sensitive: false }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :description, length: { maximum: 5000 }
  validates :selection_mode, inclusion: { in: %w[classification dynamic] }
  validate :valid_definition
  before_validation :normalize_name

  scope :ordered, -> { order(:position, :name, :id) }
  scope :active, -> { where(active: true) }
  scope :classifications, -> { where(selection_mode: 'classification') }

  private

  def valid_definition
    message = JrcCustomers::SegmentCriteria.error(criteria, mode: selection_mode)
    errors.add(:criteria, message) if message
    errors.add(:modules, 'contains an unsupported module') unless modules.is_a?(Array) && (modules - MODULES).empty?
  end

  def normalize_name
    self.name = name.to_s.strip.gsub(/\s+/, ' ').presence
  end
end
