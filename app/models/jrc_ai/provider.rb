# == Schema Information
#
# Table name: jrc_ai_providers
#
#  id                   :bigint           not null, primary key
#  active               :boolean          default(TRUE), not null
#  advanced_model       :string
#  api_key              :text
#  base_url             :string
#  default_model        :string
#  default_provider     :boolean          default(FALSE), not null
#  fast_model           :string
#  last_error           :text
#  last_validated_at    :datetime
#  monthly_budget_cents :bigint
#  monthly_token_limit  :bigint
#  name                 :string           not null
#  provider_type        :string           not null
#  settings             :jsonb            not null
#  status               :string           default("not_validated"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  created_by_id        :bigint
#
# Indexes
#
#  idx_jrc_ai_one_default_provider_per_account    (account_id) UNIQUE WHERE (default_provider = true)
#  index_jrc_ai_providers_on_account_id           (account_id)
#  index_jrc_ai_providers_on_account_id_and_name  (account_id,name) UNIQUE
#  index_jrc_ai_providers_on_created_by_id        (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
module JrcAi
  class Provider < ApplicationRecord
    self.table_name = 'jrc_ai_providers'

    PROVIDER_TYPES = %w[openai azure_openai google_gemini anthropic custom].freeze
    STATUSES = %w[not_validated configured error disabled].freeze
    OPENAI_COMPATIBLE_TYPES = %w[openai azure_openai custom].freeze

    belongs_to :account
    belongs_to :created_by, class_name: 'User', optional: true
    has_many :usage_events, class_name: 'JrcAi::UsageEvent', foreign_key: :provider_id, dependent: :nullify

    encrypts :api_key

    validates :name, :provider_type, presence: true
    validates :name, uniqueness: { scope: :account_id }
    validates :provider_type, inclusion: { in: PROVIDER_TYPES }
    validates :status, inclusion: { in: STATUSES }
    validates :monthly_token_limit, :monthly_budget_cents,
              numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

    validate :valid_usage_policy

    scope :enabled, -> { where(active: true) }
    scope :preferred_first, -> { order(default_provider: :desc, active: :desc, name: :asc) }

    before_validation :normalize_fields
    before_save :clear_other_defaults, if: :becoming_default?

    def api_key_configured?
      api_key.present?
    end

    def masked_api_key
      return nil unless api_key_configured?

      suffix = api_key.to_s.last(4)
      "#{'*' * 12}#{suffix}"
    end

    def runtime_supported?
      %w[openai custom anthropic google_gemini].include?(provider_type)
    end

    def openai_compatible?
      OPENAI_COMPATIBLE_TYPES.include?(provider_type)
    end

    def request_base_url
      value = base_url.to_s.strip
      value = JrcAi::ModelCatalogue::BASES[provider_type].to_s if value.blank?
      return value.chomp('/') if provider_type == 'google_gemini'
      value = value.chomp('/')
      return value if value.end_with?('/v1')

      "#{value}/v1"
    end

    private

    def valid_usage_policy
      policy = settings['usage_policy']
      errors.add(:settings, 'invalid usage policy') unless policy.nil? || %w[provider local].include?(policy)
    end

    def normalize_fields
      self.name = name.to_s.strip
      self.provider_type = provider_type.to_s.strip
      self.base_url = base_url.to_s.strip.presence
      self.default_model = default_model.to_s.strip.presence
      self.fast_model = fast_model.to_s.strip.presence
      self.advanced_model = advanced_model.to_s.strip.presence
      self.status = 'disabled' unless active?
      self.status = 'not_validated' if active? && status == 'disabled'
    end

    def becoming_default?
      default_provider? && will_save_change_to_default_provider?
    end

    def clear_other_defaults
      self.class.where(account_id: account_id).where.not(id: id).update_all(default_provider: false)
    end
  end
end
