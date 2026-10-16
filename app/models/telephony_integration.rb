# == Schema Information
#
# Table name: telephony_integrations
#
#  id                  :bigint           not null, primary key
#  cdr_api_version     :string           default("v1.4"), not null
#  cdr_base_url        :string           default("https://portal-cloud.jrcpabx.com.br"), not null
#  cdr_token           :text
#  default_period_days :integer          default(7), not null
#  history_enabled     :boolean          default(FALSE), not null
#  provider            :string           default("hodupbx"), not null
#  tenant_type         :string           default("TENANT"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_telephony_integrations_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class TelephonyIntegration < ApplicationRecord
  PROVIDERS = %w[hodupbx].freeze
  PERIODS = [1, 7, 30].freeze

  belongs_to :account

  encrypts :cdr_token
  encrypts :pabx_username, :pabx_password

  validate :valid_pabx_settings

  validates :account_id, uniqueness: true
  validates :provider, inclusion: { in: PROVIDERS }
  validates :cdr_base_url, :cdr_api_version, :tenant_type, presence: true
  validates :cdr_api_version, format: { with: /\Av\d+(?:\.\d+)*\z/ }
  validates :tenant_type, format: { with: /\A[A-Z_]+\z/ }
  validates :default_period_days, inclusion: { in: PERIODS }
  validates :cdr_token, presence: true, if: :history_enabled?
  validate :secure_cdr_base_url

  def configured?
    history_enabled? && cdr_token.present? && cdr_base_url.present? && cdr_api_version.present?
  end

  private

  def valid_pabx_settings
    Pabx::Settings.new(self).validate! if pabx_settings.present?
  rescue Pabx::Error => e
    errors.add(:pabx_settings, e.code)
  end

  def secure_cdr_base_url
    uri = URI.parse(cdr_base_url.to_s)
    return if uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.blank?

    errors.add(:cdr_base_url, 'deve ser uma URL HTTPS válida')
  rescue URI::InvalidURIError
    errors.add(:cdr_base_url, 'deve ser uma URL HTTPS válida')
  end
end
