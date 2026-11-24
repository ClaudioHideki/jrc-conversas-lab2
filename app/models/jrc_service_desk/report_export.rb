# frozen_string_literal: true

class JrcServiceDesk::ReportExport < JrcServiceDesk::UnitRecord
  FORMATS = %w[csv_summary csv_detailed xlsx pdf].freeze
  MANAGERIAL_FORMATS = %w[html xlsx pdf csv].freeze
  MANAGERIAL_BLOB_MARKER = 'jrc_sd_managerial_export'
  belongs_to :account_user
  has_one_attached :file
  validates :format, inclusion: { in: ->(export) { export.class.formats_for(export.kind) } }
  validates :state, inclusion: { in: %w[queued processing ready failed expired] }
  validates :expected_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :expires_at, presence: true
  validate :owner_in_account
  scope :for_kind, ->(kind) { where("COALESCE(metadata->>'report_kind', 'operational') = ?", kind) }

  def limit
    self.class.limit_for(format, kind: kind)
  end

  def kind
    metadata.fetch('report_kind', 'operational')
  end

  def managerial?
    kind == 'managerial'
  end

  def self.formats_for(kind)
    kind == 'managerial' ? MANAGERIAL_FORMATS : FORMATS
  end

  def self.limit_for(format, kind: 'operational')
    return format == 'html' ? 5_000 : 10_000 if kind == 'managerial'

    key = format == 'xlsx' ? 'JRC_SD_XLSX_EXPORT_LIMIT' : 'JRC_SD_REPORT_EXPORT_LIMIT'
    Integer(ENV.fetch(key, format == 'xlsx' ? '20000' : '100000')).clamp(1, 100_000)
  end

  private

  def owner_in_account
    validate_account_reference(:account_user)
  end
end
