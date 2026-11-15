# == Schema Information
#
# Table name: canned_responses
#
#  id         :integer          not null, primary key
#  content    :text
#  short_code :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :integer          not null
#

class CannedResponse < ApplicationRecord
  validates :content, presence: true
  validates :short_code, presence: true
  validates :account, presence: true
  validates :short_code, uniqueness: { scope: :account_id }

  belongs_to :account
  has_one_attached :file
  validate :safe_quick_reply_file

  def file_metadata
    return unless file.attached?

    { id: file.id, filename: file.filename.to_s, content_type: file.content_type, byte_size: file.byte_size }
  end

  private

  def safe_quick_reply_file
    return unless file.attached?

    limit = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    limit = 40 if limit <= 0
    errors.add(:file, 'size is too big') if file.byte_size > limit.megabytes
    errors.add(:file, 'must not be empty') unless file.byte_size.positive?
    allowed = %w[image/jpeg image/png image/webp image/gif] + Attachment::ACCEPTABLE_FILE_TYPES
    errors.add(:file, 'type not supported') unless allowed.include?(file.content_type)
  end

  scope :order_by_search, lambda { |search|
    short_code_starts_with = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 1', "#{search}%"])
    short_code_like = sanitize_sql_array(['WHEN short_code ILIKE ? THEN 0.5', "%#{search}%"])
    content_like = sanitize_sql_array(['WHEN content ILIKE ? THEN 0.2', "%#{search}%"])

    order_clause = "CASE #{short_code_starts_with} #{short_code_like} #{content_like} ELSE 0 END"

    order(Arel.sql(order_clause) => :desc)
  }
end
