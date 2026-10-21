# == Schema Information
#
# Table name: jrc_campaign_consents
#
#  id             :bigint           not null, primary key
#  evidence       :text             not null
#  granted_at     :datetime         not null
#  phone_number   :string           not null
#  revoked_at     :datetime
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  recorded_by_id :bigint           not null
#
# Indexes
#
#  index_jrc_campaign_consents_active_phone       (account_id,phone_number) UNIQUE WHERE (revoked_at IS NULL)
#  index_jrc_campaign_consents_on_account_id      (account_id)
#  index_jrc_campaign_consents_on_recorded_by_id  (recorded_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (recorded_by_id => users.id)
#
class JrcCampaigns::Consent < ApplicationRecord
  self.table_name = 'jrc_campaign_consents'

  belongs_to :account
  belongs_to :recorded_by, class_name: 'User'
  belongs_to :supersedes, class_name: 'JrcCampaigns::Consent', optional: true
  has_one :superseding_consent, class_name: 'JrcCampaigns::Consent', foreign_key: :supersedes_id, inverse_of: :supersedes
  scope :active, -> { where(revoked_at: nil).where('granted_at <= ?', Time.current) }

  before_validation { self.phone_number = JrcCampaigns::PhoneNormalizer.call(phone_number) }
  validates :phone_number, :evidence, :granted_at, presence: true
  validates :phone_number, format: { with: /\A\+[1-9]\d{7,14}\z/ }
  validates :purpose, inclusion: { in: %w[whatsapp_campaigns] }, allow_nil: true
  validates :phone_number, uniqueness: { scope: :account_id, conditions: -> { where(revoked_at: nil) } }, if: -> { revoked_at.nil? }
  validate :supersedes_same_destination

  private

  def supersedes_same_destination
    return unless supersedes
    return if supersedes.account_id == account_id && supersedes.phone_number == phone_number && supersedes.revoked_at.present?

    errors.add(:supersedes, 'deve ser um registro encerrado da mesma conta e telefone')
  end
end
