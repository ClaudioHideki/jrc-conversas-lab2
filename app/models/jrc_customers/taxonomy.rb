class JrcCustomers::Taxonomy < ApplicationRecord
  self.table_name = 'jrc_customer_taxonomies'

  KINDS = %w[segment].freeze

  belongs_to :account

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id kind], case_sensitive: false }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  before_validation :normalize_name

  scope :ordered, -> { order(:position, :name, :id) }
  scope :active, -> { where(active: true) }

  private

  def normalize_name
    self.name = name.to_s.strip.gsub(/\s+/, ' ').presence
  end
end
