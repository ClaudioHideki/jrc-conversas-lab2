# frozen_string_literal: true

class JrcServiceDesk::ReportExport < JrcServiceDesk::UnitRecord
  FORMATS = %w[csv_summary csv_detailed xlsx pdf].freeze
  belongs_to :account_user
  has_one_attached :file
  validates :format, inclusion: { in: FORMATS }
  validates :state, inclusion: { in: %w[queued processing ready failed expired] }
  validates :expected_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true
  validate :owner_in_account

  def limit
    self.class.limit_for(format)
  end

  def self.limit_for(format)
    key = format == 'xlsx' ? 'JRC_SD_XLSX_EXPORT_LIMIT' : 'JRC_SD_REPORT_EXPORT_LIMIT'
    Integer(ENV.fetch(key, format == 'xlsx' ? '20000' : '100000')).clamp(1, 100_000)
  end

  private

  def owner_in_account
    validate_account_reference(:account_user)
  end
end
