# == Schema Information
#
# Table name: jrc_campaigns
#
#  id                   :bigint           not null, primary key
#  audience_config      :jsonb            not null
#  audience_type        :string           default("all_contacts"), not null
#  clicked_count        :integer          default(0), not null
#  completed_at         :datetime
#  conversation_mode    :string           default("reply_only"), not null
#  delay_max_seconds    :integer          default(20), not null
#  delay_min_seconds    :integer          default(5), not null
#  delivered_count      :integer          default(0), not null
#  delivery_channel     :string           default("whatsapp"), not null
#  estimated_recipients :integer          default(0), not null
#  failed_count         :integer          default(0), not null
#  follow_up_config     :jsonb            not null
#  last_error           :text
#  last_execution_at    :datetime
#  message_body         :text             default(""), not null
#  metadata             :jsonb            not null
#  name                 :string           not null
#  paused_at            :datetime
#  read_count           :integer          default(0), not null
#  recurrence_config    :jsonb            not null
#  replied_count        :integer          default(0), not null
#  rotation_mode        :string           default("round_robin"), not null
#  scheduled_at         :datetime
#  sending_window       :jsonb            not null
#  sent_count           :integer          default(0), not null
#  started_at           :datetime
#  status               :string           default("draft"), not null
#  trigger_type         :string           default("manual"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  created_by_id        :bigint
#  inbox_id             :bigint
#
# Indexes
#
#  index_jrc_campaigns_on_account_id                       (account_id)
#  index_jrc_campaigns_on_account_id_and_delivery_channel  (account_id,delivery_channel)
#  index_jrc_campaigns_on_account_id_and_scheduled_at      (account_id,scheduled_at)
#  index_jrc_campaigns_on_account_id_and_status            (account_id,status)
#  index_jrc_campaigns_on_created_by_id                    (created_by_id)
#  index_jrc_campaigns_on_inbox_id                         (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class JrcCampaigns::Campaign < ApplicationRecord
  self.table_name = 'jrc_campaigns'

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true

  has_many :campaign_inboxes, class_name: 'JrcCampaigns::CampaignInbox', dependent: :destroy
  has_many :inboxes, through: :campaign_inboxes
  has_many :steps, -> { order(:position) }, class_name: 'JrcCampaigns::Step', dependent: :destroy
  has_many :executions, -> { order(run_number: :desc) }, class_name: 'JrcCampaigns::Execution', dependent: :destroy
  has_many :recipients, class_name: 'JrcCampaigns::Recipient', dependent: :destroy
  has_many :events, class_name: 'JrcCampaigns::Event', dependent: :destroy

  accepts_nested_attributes_for :steps, allow_destroy: true
  accepts_nested_attributes_for :campaign_inboxes, allow_destroy: true

  STATUSES = %w[draft scheduled running paused completed canceled].freeze
  TRIGGERS = %w[manual scheduled].freeze
  AUDIENCES = %w[all_contacts label inbox crm_stage sanitized_list].freeze
  ROTATIONS = %w[round_robin least_used priority random weighted].freeze
  CONVERSATION_MODES = %w[reply_only pending open].freeze
  RECURRENCES = %w[none daily weekly monthly custom].freeze
  DELIVERY_CHANNELS = %w[whatsapp email].freeze
  InboxLink = Data.define(:inbox, :weight)

  enum :status, STATUSES.index_with(&:itself)

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :trigger_type, inclusion: { in: TRIGGERS }
  validates :audience_type, inclusion: { in: AUDIENCES }
  validates :rotation_mode, inclusion: { in: ROTATIONS }
  validates :conversation_mode, inclusion: { in: CONVERSATION_MODES }
  validates :delivery_channel, inclusion: { in: DELIVERY_CHANNELS }
  validates :delay_min_seconds, :delay_max_seconds, numericality: { greater_than_or_equal_to: 0 }
  validates :scheduled_at, presence: true, if: -> { trigger_type == 'scheduled' }
  validate :delay_range_is_valid
  validate :sending_window_is_valid
  validate :recurrence_is_valid
  validate :legacy_inbox_belongs_to_account

  before_save :refresh_estimated_recipients, if: :audience_changed?

  def launch!
    with_lock { launch_approved! }
  end

  def request_review!
    JrcCampaigns::ApprovalService.new(self).request_review!
  end

  def approve!(user, digest)
    JrcCampaigns::ApprovalService.new(self).approve!(user, digest)
  end

  def approval_valid?
    JrcCampaigns::ApprovalService.new(self).valid?
  end

  def ensure_approved!
    JrcCampaigns::ApprovalService.new(self).ensure_valid!
  end

  def launch_approved!
    ensure_status!('draft')
    ensure_approved!
    raise ActiveRecord::RecordInvalid, self if steps.empty?
    raise ActiveRecord::RecordInvalid, self if sending_inbox_links.empty?

    if trigger_type == 'scheduled' && scheduled_at.present? && scheduled_at.future?
      update!(status: 'scheduled', last_error: nil)
      JrcCampaigns::LaunchJob.set(wait_until: scheduled_at).perform_later(id, scheduled_at.to_i)
    else
      update!(status: 'running', started_at: Time.current, paused_at: nil, last_error: nil)
      JrcCampaigns::LaunchJob.perform_later(id)
    end
  end

  def pause!
    ensure_status!('running')
    update!(status: 'paused', paused_at: Time.current)
  end

  def resume!
    ensure_status!('paused')
    update!(status: 'running', paused_at: nil)
    JrcCampaigns::ResumeService.new(self).perform
  end

  def cancel!
    update!(status: 'canceled')
    executions.where(status: %w[queued running]).update_all( # rubocop:disable Rails/SkipsModelValidations
      status: 'canceled', completed_at: Time.current
    )
  end

  def enabled_campaign_inboxes
    campaign_inboxes.includes(inbox: :channel).select(&:enabled?)
  end

  def sending_inbox_links
    links = enabled_campaign_inboxes
    return links if links.any?
    return [] unless accepts_sending_inbox?(inbox)

    [InboxLink.new(inbox: inbox, weight: 1)]
  end

  def accepts_sending_inbox?(candidate)
    return false unless candidate && candidate.account_id == account_id
    return true if candidate.channel_type == expected_channel_type

    whatsapp? && (JrcCampaigns::EvolutionConnector.for(candidate).present? || JrcCampaigns::BrokerConnector.for(candidate).present?)
  end

  def evolution_connectors
    sending_inbox_links.filter_map { |link| JrcCampaigns::EvolutionConnector.for(link.inbox) }
  end

  def broker_connectors
    sending_inbox_links.filter_map { |link| JrcCampaigns::BrokerConnector.for(link.inbox) }
  end

  def ensure_sender_compatibility!
    invalid = sending_inbox_links.any? { |link| !accepts_sending_inbox?(link.inbox) }
    connectors = evolution_connectors
    brokers = broker_connectors
    reason = if invalid
               'Caixa remetente não autorizada para esta conta e canal.'
               elsif brokers.any? && sending_inbox_links.size != brokers.size
                 'Use campanhas separadas para Broker, Evolution e WhatsApp oficial.'
             elsif connectors.any? && sending_inbox_links.size != connectors.size
               'Use campanhas separadas para Evolution Demo e WhatsApp oficial.'
               elsif (connectors.any? || brokers.any?) && steps.any? { |step| step.kind == 'template' }
               'Templates Meta exigem uma caixa WhatsApp oficial.'
             elsif connectors.any? && delay_min_seconds < connectors.map(&:min_interval_seconds).max
               'O intervalo da campanha Evolution deve respeitar o mínimo configurado para a caixa.'
             end
    return unless reason

    errors.add(:base, reason)
    raise ActiveRecord::RecordInvalid, self
  end

  def latest_execution
    executions.first
  end

  def whatsapp?
    delivery_channel == 'whatsapp'
  end

  def email?
    delivery_channel == 'email'
  end

  def expected_channel_type
    email? ? 'Channel::Email' : 'Channel::Whatsapp'
  end

  def editable?
    status.in?(%w[draft scheduled])
  end

  def refresh_counters!
    scope = recipients
    update_columns( # rubocop:disable Rails/SkipsModelValidations
      sent_count: scope.where.not(sent_at: nil).count,
      failed_count: scope.where(status: 'failed').count,
      delivered_count: scope.where.not(delivered_at: nil).count,
      read_count: scope.where.not(read_at: nil).count,
      replied_count: scope.where.not(replied_at: nil).count
    )
  end

  private

  def legacy_inbox_belongs_to_account
    errors.add(:inbox, 'deve pertencer à mesma conta') if inbox && inbox.account_id != account_id
  end


  def ensure_status!(*allowed)
    return if status.in?(allowed)

    errors.add(:status, "não permite esta ação no estado #{status}")
    raise ActiveRecord::RecordInvalid, self
  end

  def delay_range_is_valid
    return unless delay_min_seconds && delay_max_seconds
    return if delay_max_seconds >= delay_min_seconds

    errors.add(:delay_max_seconds, 'deve ser maior ou igual ao intervalo mínimo')
  end

  def sending_window_is_valid
    window = sending_window.to_h.with_indifferent_access
    days = Array(window[:days]).map(&:to_i)
    errors.add(:sending_window, 'deve ter pelo menos um dia permitido') if days.empty?
    errors.add(:sending_window, 'contém um dia inválido') if days.any? { |day| !day.between?(0, 6) }

    start_time = window[:start].to_s
    end_time = window[:end].to_s
    valid_time = /\A(?:[01]\d|2[0-3]):[0-5]\d\z/
    unless start_time.match?(valid_time) && end_time.match?(valid_time)
      errors.add(:sending_window, 'possui horário inválido')
      return
    end

    errors.add(:sending_window, 'deve terminar depois do horário inicial') if end_time <= start_time
  end

  def recurrence_is_valid
    config = recurrence_config.to_h.with_indifferent_access
    kind = config[:type].presence || 'none'
    unless RECURRENCES.include?(kind)
      errors.add(:recurrence_config, 'possui recorrência inválida')
      return
    end

    if kind == 'custom' && config[:interval_days].to_i <= 0
      errors.add(:recurrence_config, 'deve informar um intervalo em dias maior que zero')
    end
  end

  def audience_changed?
    new_record? || will_save_change_to_audience_type? || will_save_change_to_audience_config? ||
      will_save_change_to_inbox_id? || will_save_change_to_delivery_channel?
  end

  def refresh_estimated_recipients
    self.estimated_recipients = JrcCampaigns::AudienceResolver.new(self).estimated_count
  end
end
