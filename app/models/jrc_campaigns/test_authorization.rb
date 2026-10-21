class JrcCampaigns::TestAuthorization < ApplicationRecord
  self.table_name = 'jrc_campaign_test_authorizations'
  IDENTITY_FIELDS = %w[base_url instance sender_number].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :recorded_by, class_name: 'User'
  belongs_to :test_delivery, class_name: 'JrcCampaigns::TestDelivery', optional: true

  scope :available, -> { where(consumed_at: nil, revoked_at: nil).where('granted_at <= ?', Time.current) }
  before_validation { self.phone_number = JrcCampaigns::PhoneNormalizer.call(phone_number) }
  validates :phone_number, format: { with: /\A\+[1-9]\d{7,14}\z/ }
  validates :evidence, :granted_at, :connector_snapshot, presence: true
  validates :phone_number, uniqueness: {
    scope: [:account_id, :inbox_id], conditions: -> { where(consumed_at: nil, revoked_at: nil) }
  }, if: -> { consumed_at.nil? && revoked_at.nil? }
  validate :same_account

  attr_readonly :account_id, :inbox_id, :recorded_by_id, :phone_number, :evidence, :granted_at, :connector_snapshot

  def matches_connector?(connector)
    connector_snapshot.slice(*IDENTITY_FIELDS) == connector.public_configuration.slice(*IDENTITY_FIELDS)
  end

  private

  def same_account
    errors.add(:inbox, 'deve pertencer à mesma conta') if inbox && inbox.account_id != account_id
    errors.add(:test_delivery, 'deve corresponder à conta, caixa e destinatário') if test_delivery &&
      [test_delivery.account_id, test_delivery.inbox_id, test_delivery.phone_number] != [account_id, inbox_id, phone_number]
  end
end
