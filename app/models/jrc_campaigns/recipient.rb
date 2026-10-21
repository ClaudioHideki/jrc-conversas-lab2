# == Schema Information
#
# Table name: jrc_campaign_recipients
#
#  id              :bigint           not null, primary key
#  delivered_at    :datetime
#  destination     :string           not null
#  email           :string
#  error_message   :text
#  failed_at       :datetime
#  metadata        :jsonb            not null
#  name            :string
#  phone_number    :string
#  read_at         :datetime
#  replied_at      :datetime
#  scheduled_at    :datetime
#  sent_at         :datetime
#  source          :string           default("contact"), not null
#  status          :string           default("queued"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  campaign_id     :bigint           not null
#  contact_id      :integer
#  conversation_id :integer
#  execution_id    :bigint           not null
#  inbox_id        :integer
#
# Indexes
#
#  index_jrc_campaign_recipients_on_campaign_id                    (campaign_id)
#  index_jrc_campaign_recipients_on_campaign_id_and_email          (campaign_id,email)
#  index_jrc_campaign_recipients_on_campaign_id_and_phone_number   (campaign_id,phone_number)
#  index_jrc_campaign_recipients_on_contact_id                     (contact_id)
#  index_jrc_campaign_recipients_on_conversation_id                (conversation_id)
#  index_jrc_campaign_recipients_on_execution_id                   (execution_id)
#  index_jrc_campaign_recipients_on_execution_id_and_email         (execution_id,email) UNIQUE WHERE (email IS NOT NULL)
#  index_jrc_campaign_recipients_on_execution_id_and_phone_number  (execution_id,phone_number) UNIQUE WHERE (phone_number IS NOT NULL)
#  index_jrc_campaign_recipients_on_execution_id_and_status        (execution_id,status)
#  index_jrc_campaign_recipients_on_inbox_id                       (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => jrc_campaigns.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (execution_id => jrc_campaign_executions.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class JrcCampaigns::Recipient < ApplicationRecord
  self.table_name = 'jrc_campaign_recipients'

  STATUSES = %w[queued processing sent delivered read replied failed skipped canceled].freeze

  enum :status, STATUSES.index_with(&:itself)


  belongs_to :campaign, class_name: 'JrcCampaigns::Campaign'
  belongs_to :execution, class_name: 'JrcCampaigns::Execution'
  belongs_to :contact, optional: true
  belongs_to :inbox, optional: true
  belongs_to :conversation, optional: true
  has_many :deliveries, class_name: 'JrcCampaigns::Delivery', dependent: :destroy
  has_many :events, class_name: 'JrcCampaigns::Event', dependent: :destroy

  validates :phone_number, presence: true, if: -> { campaign&.whatsapp? }
  validates :email, presence: true, if: -> { campaign&.email? }
  validates :destination, presence: true
  validates :status, inclusion: { in: STATUSES }
end
