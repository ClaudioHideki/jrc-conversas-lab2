# == Schema Information
#
# Table name: accounts
#
#  id                    :integer          not null, primary key
#  auto_resolve_duration :integer
#  custom_attributes     :jsonb
#  domain                :string(100)
#  feature_flags         :bigint           default(0), not null
#  feature_flags_ext_1   :bigint           default(0), not null
#  internal_attributes   :jsonb            not null
#  limits                :jsonb
#  locale                :integer          default("en")
#  name                  :string           not null
#  settings              :jsonb
#  status                :integer          default("active")
#  support_email         :string(100)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_accounts_on_status  (status)
#

class Account < ApplicationRecord
  has_many :jrc_flows, dependent: :destroy
  has_many :sip_credentials, dependent: :destroy
  has_many :video_conference_settings, dependent: :destroy
  has_one :telephony_integration, dependent: :destroy
  has_one :whatsapp_calling_configuration, dependent: :destroy
  # used for multi-flag bitset columns
  include FlagShihTzu
  include Reportable
  include Featurable
  include CacheKeys
  include CaptainFeaturable
  include AccountEmailRateLimitable
  include AccountSettingsSchema

  DEFAULT_QUERY_SETTING = {
    flag_query_mode: :bit_operator,
    check_for_column: false
  }.freeze
  SUSPENSION_CATEGORIES = %w[spam non_payment other].freeze

  attr_accessor :suspension_category, :suspension_reason

  validates :name, presence: true
  # `domain` is the inbound email domain used to construct reply addresses
  # (see `inbound_email_domain`). Do not repurpose it for a website or any
  # non-mail-related domain.
  validates :domain, length: { maximum: 100 }
  validates_with JsonSchemaValidator,
                 schema: SETTINGS_PARAMS_SCHEMA,
                 attribute_resolver: ->(record) { record.settings }
  validate :validate_reporting_timezone
  validate :validate_support_email_format, if: :will_save_change_to_support_email?

  store_accessor :settings, :auto_resolve_after, :auto_resolve_message, :auto_resolve_ignore_waiting

  store_accessor :settings, :audio_transcriptions, :auto_resolve_label
  store_accessor :settings, :captain_models, :captain_features
  store_accessor :settings, :reporting_timezone
  store_accessor :settings, :keep_pending_on_bot_failure
  store_accessor :settings, :captain_auto_resolve_mode, :captain_false_promise_harness_enabled
  include AccountCaptainAutoResolve

  has_many :account_users, dependent: :destroy_async
  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :agent_bots, dependent: :destroy_async
  has_many :api_channels, dependent: :destroy_async, class_name: '::Channel::Api'
  has_many :articles, dependent: :destroy_async, class_name: '::Article'
  has_many :assignment_policies, dependent: :destroy_async
  has_many :automation_rules, dependent: :destroy_async
  has_many :macros, dependent: :destroy_async
  has_many :campaigns, dependent: :destroy_async
  has_many :canned_responses, dependent: :destroy_async
  has_many :categories, dependent: :destroy_async, class_name: '::Category'
  has_many :master_companies, class_name: 'JrcCustomers::Company'
  has_many :contacts, dependent: :destroy_async
  has_many :conversations, dependent: :destroy_async
  has_many :csat_survey_responses, dependent: :destroy_async
  has_many :custom_attribute_definitions, dependent: :destroy_async
  has_many :custom_filters, dependent: :destroy_async
  has_many :dashboard_apps, dependent: :destroy_async
  has_many :data_imports, dependent: :destroy_async
  has_many :email_channels, dependent: :destroy_async, class_name: '::Channel::Email'
  has_many :facebook_pages, dependent: :destroy_async, class_name: '::Channel::FacebookPage'
  has_many :instagram_channels, dependent: :destroy_async, class_name: '::Channel::Instagram'
  has_many :tiktok_channels, dependent: :destroy_async, class_name: '::Channel::Tiktok'
  has_many :hooks, dependent: :destroy_async, class_name: 'Integrations::Hook'
  has_many :inboxes, dependent: :destroy_async
  has_many :labels, dependent: :destroy_async
  has_many :line_channels, dependent: :destroy_async, class_name: '::Channel::Line'
  has_many :mentions, dependent: :destroy_async
  has_many :messages, dependent: :destroy_async
  has_many :notes, dependent: :destroy_async
  has_many :notification_settings, dependent: :destroy_async
  has_many :notifications, dependent: :destroy_async
  has_many :portals, dependent: :destroy_async, class_name: '::Portal'
  has_many :sms_channels, dependent: :destroy_async, class_name: '::Channel::Sms'
  has_many :teams, dependent: :destroy_async
  has_many :telegram_channels, dependent: :destroy_async, class_name: '::Channel::Telegram'
  has_many :twilio_sms, dependent: :destroy_async, class_name: '::Channel::TwilioSms'
  has_many :twitter_profiles, dependent: :destroy_async, class_name: '::Channel::TwitterProfile'
  has_many :users, through: :account_users
  has_many :web_widgets, dependent: :destroy_async, class_name: '::Channel::WebWidget'
  has_many :webhooks, dependent: :destroy_async
  has_many :whatsapp_channels, dependent: :destroy_async, class_name: '::Channel::Whatsapp'
  has_many :working_hours, dependent: :destroy_async
  has_many :sales_pipelines, dependent: :destroy_async
  has_many :sales_stages, dependent: :destroy_async
  has_many :sales_opportunities, dependent: :destroy_async
  has_many :sales_activities, dependent: :destroy_async
  has_many :sales_loss_reasons, dependent: :destroy_async
  has_many :jrc_crm_pipelines, class_name: 'JrcCrm::Pipeline', dependent: :destroy_async
  has_many :jrc_crm_stages, class_name: 'JrcCrm::Stage', dependent: :destroy_async
  has_many :jrc_crm_lost_reasons, class_name: 'JrcCrm::LostReason', dependent: :destroy_async
  has_many :jrc_crm_leads, class_name: 'JrcCrm::Lead', dependent: :destroy_async
  has_many :jrc_crm_deals, class_name: 'JrcCrm::Deal', dependent: :destroy_async
  has_many :jrc_crm_products, class_name: 'JrcCrm::Product', dependent: :destroy_async
  has_many :jrc_crm_proposals, class_name: 'JrcCrm::Proposal', dependent: :destroy_async
  has_many :jrc_crm_sales_orders, class_name: 'JrcCrm::SalesOrder', dependent: :destroy_async
  has_many :jrc_crm_contracts, class_name: 'JrcCrm::Contract', dependent: :destroy_async
  has_many :jrc_crm_sales_commissions, class_name: 'JrcCrm::SalesCommission', dependent: :destroy_async
  has_many :jrc_crm_commission_programs, class_name: 'JrcCrm::CommissionProgram', dependent: :destroy_async
  has_many :jrc_crm_backoffice_requests, class_name: 'JrcCrm::BackofficeRequest', dependent: :destroy_async
  has_many :jrc_crm_invoices, class_name: 'JrcCrm::Invoice', dependent: :destroy_async
  has_many :jrc_crm_payments, class_name: 'JrcCrm::Payment', dependent: :destroy_async
  has_many :jrc_crm_contract_templates, class_name: 'JrcCrm::ContractTemplate', dependent: :destroy_async
  has_many :jrc_crm_sales_goals, class_name: 'JrcCrm::SalesGoal', dependent: :destroy_async
  has_many :jrc_crm_activities, class_name: 'JrcCrm::Activity', dependent: :destroy_async
  has_many :jrc_crm_follow_ups, class_name: 'JrcCrm::FollowUp', dependent: :destroy_async
  has_many :jrc_crm_audit_events, class_name: 'JrcCrm::AuditEvent', dependent: :destroy_async
  has_many :jrc_crm_automation_rules, class_name: 'JrcCrm::AutomationRule', dependent: :destroy_async
  has_many :jrc_crm_import_batches, class_name: 'JrcCrm::ImportBatch', dependent: :destroy_async
  has_many :jrc_crm_campaigns, class_name: 'JrcCrm::Campaign', dependent: :destroy_async
  has_many :jrc_crm_custom_attribute_definitions, class_name: 'JrcCrm::CustomAttributeDefinition', dependent: :destroy_async
  has_many :jrc_crm_organizations, class_name: 'JrcCrm::Organization', dependent: :destroy_async
  has_many :jrc_crm_deal_conversations, class_name: 'JrcCrm::DealConversation', dependent: :destroy_async
  has_many :jrc_campaigns, class_name: 'JrcCampaigns::Campaign', dependent: :destroy_async
  has_many :jrc_campaign_blacklists, class_name: 'JrcCampaigns::Blacklist', dependent: :destroy_async
  has_many :jrc_campaign_sanitized_lists, class_name: 'JrcCampaigns::SanitizedList', dependent: :destroy_async
  has_many :jrc_campaign_media_assets, class_name: 'JrcCampaigns::MediaAsset', dependent: :destroy_async
  has_many :jrc_ai_providers, class_name: 'JrcAi::Provider', dependent: :destroy_async
  has_many :jrc_ai_usage_events, class_name: 'JrcAi::UsageEvent', dependent: :destroy_async

  has_one_attached :contacts_export

  enum :locale, LANGUAGES_CONFIG.map { |key, val| [val[:iso_639_1_code], key] }.to_h, prefix: true
  enum :status, { active: 0, suspended: 1 }

  scope :with_auto_resolve, -> { where("(settings ->> 'auto_resolve_after')::int IS NOT NULL") }

  before_validation :validate_limit_keys
  after_create_commit :notify_creation
  after_update_commit :clear_unread_conversation_counts_cache, if: :saved_change_to_feature_conversation_unread_counts?
  after_destroy :remove_account_sequences

  def agents
    users.where(account_users: { role: :agent })
  end

  def administrators
    users.where(account_users: { role: :administrator })
  end

  def all_conversation_tags
    # returns array of tags
    conversation_ids = conversations.pluck(:id)
    ActsAsTaggableOn::Tagging.includes(:tag)
                             .where(context: 'labels',
                                    taggable_type: 'Conversation',
                                    taggable_id: conversation_ids)
                             .map { |tagging| tagging.tag.name }
  end

  def webhook_data
    {
      id: id,
      name: name
    }
  end

  def suspension_history
    internal_attributes['suspensions'] || []
  end

  def inbound_email_domain
    domain.presence || GlobalConfig.get('MAILER_INBOUND_EMAIL_DOMAIN')['MAILER_INBOUND_EMAIL_DOMAIN'] || ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN',
                                                                                                                   false)
  end

  def support_email
    super.presence || ENV.fetch('MAILER_SENDER_EMAIL') { GlobalConfig.get('MAILER_SUPPORT_EMAIL')['MAILER_SUPPORT_EMAIL'] }
  end

  def usage_limits
    {
      agents: ChatwootApp.max_limit.to_i,
      inboxes: ChatwootApp.max_limit.to_i
    }
  end

  def api_and_webhooks_enabled?
    true
  end

  def locale_english_name
    # the locale can also be something like pt_BR, en_US, fr_FR, etc.
    # the format is `<locale_code>_<country_code>`
    # we need to extract the language code from the locale
    account_locale = locale&.split('_')&.first
    ISO_639.find(account_locale)&.english_name&.downcase || 'english'
  end

  def onboarding_step
    step = custom_attributes['onboarding_step']
    return nil if step.blank?

    enrichment_key = format(Redis::Alfred::ACCOUNT_ONBOARDING_ENRICHMENT, account_id: id)
    Redis::Alfred.exists?(enrichment_key) ? 'enrichment' : step
  end

  def reset_cache_keys
    super
    clear_unread_conversation_counts_cache
  end

  private

  def notify_creation
    Rails.configuration.dispatcher.dispatch(ACCOUNT_CREATED, Time.zone.now, account: self)
  end

  def clear_unread_conversation_counts_cache
    ::Conversations::UnreadCounts::Store.clear_account!(id)
  end

  trigger.after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS conv_dpid_seq_%s', NEW.id);"
  end

  trigger.name('camp_dpid_before_insert').after(:insert).for_each(:row) do
    "execute format('create sequence IF NOT EXISTS camp_dpid_seq_%s', NEW.id);"
  end

  def validate_limit_keys
    # method overridden in enterprise module
  end

  def validate_reporting_timezone
    return if reporting_timezone.blank? || ActiveSupport::TimeZone[reporting_timezone].present?

    errors.add(:reporting_timezone, I18n.t('errors.account.reporting_timezone.invalid'))
  end

  def validate_support_email_format
    value = attributes['support_email']
    return if value.blank?

    parsed = Mail::Address.new(value).address
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid')) if parsed.blank?
  rescue Mail::Field::ParseError, Mail::Field::IncompleteParseError
    errors.add(:support_email, I18n.t('errors.account.support_email.invalid'))
  end

  def remove_account_sequences
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS camp_dpid_seq_#{id}")
    ActiveRecord::Base.connection.exec_query("drop sequence IF EXISTS conv_dpid_seq_#{id}")
  end
end

Account.prepend_mod_with('Account')
Account.prepend_mod_with('Account::PlanUsageAndLimits')
Account.include_mod_with('Concerns::Account')
Account.include_mod_with('Audit::Account')
